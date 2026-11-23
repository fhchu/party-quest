#!/usr/bin/env bash
# Runs the game server and the relay together. Ctrl+C stops both; if either
# exits, the other is stopped too.
#
# `dev.sh --web` also exports the client once, at start, and serves it at
# http://localhost:8060/tmp_js_export.html (the page the editor's Run in
# Browser opens). Run it on your machine, not wherever the game server is
# hosted.
set -u
cd "$(dirname "$0")" || exit 1
godot="${GODOT_BIN:-godot}"

web=false
case "${1:-}" in
	"") ;;
	--web) web=true ;;
	*) echo "usage: dev.sh [--web]" >&2; exit 2 ;;
esac

# A second copy can't get the ports, and the first may be in a terminal
# you've lost track of, so say where it is.
pidfile="${TMPDIR:-/tmp}/party-quest-dev.pid"
other="$(cat "$pidfile" 2>/dev/null)"
if [ -n "$other" ] && ps -p "$other" -o command= 2>/dev/null | grep -q dev.sh; then
	echo "dev.sh: already running as PID $other (stop it with: kill $other)" >&2
	exit 1
fi
echo $$ > "$pidfile"

# Built, not `go run`: stopping `go run` can leave its relay running.
tmp="$(mktemp -d)"
(cd relay && go build -o "$tmp/relay" .) || { rm -rf "$tmp"; exit 1; }

web_pid=""
if $web; then
	mkdir "$tmp/web"
	"$godot" --headless --path game --export-debug "Web" "$tmp/web/tmp_js_export.html" \
		|| { rm -rf "$tmp"; exit 1; }
	python3 -m http.server 8060 --bind 127.0.0.1 --directory "$tmp/web" &
	web_pid=$!
fi

"$godot" --headless --path game res://server/main.tscn &
game=$!
"$tmp/relay" &
relay=$!

# ShellCheck can't see that the EXIT trap below calls this.
# shellcheck disable=SC2329
stop() {
	kill "$game" "$relay" "$web_pid" 2>/dev/null
	wait "$game" "$relay" "$web_pid" 2>/dev/null
	rm -rf "$tmp" "$pidfile"
}
trap stop EXIT
trap 'exit 130' INT TERM

# macOS's bash has no `wait -n`, so check on both every half second.
while kill -0 "$game" 2>/dev/null && kill -0 "$relay" 2>/dev/null \
	&& { [ -z "$web_pid" ] || kill -0 "$web_pid" 2>/dev/null; }; do
	sleep 0.5
done
if ! kill -0 "$game" 2>/dev/null; then
	echo "dev.sh: the game server exited; stopping the rest" >&2
elif ! kill -0 "$relay" 2>/dev/null; then
	echo "dev.sh: the relay exited; stopping the rest" >&2
else
	echo "dev.sh: the web server exited; stopping the rest" >&2
fi
exit 1
