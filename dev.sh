#!/usr/bin/env bash
# Runs the game server and the relay together. Ctrl+C stops both; if either
# exits, the other is stopped too.
set -u
cd "$(dirname "$0")" || exit 1
godot="${GODOT_BIN:-godot}"

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

# --dev: the dev keys that end a run work (see game/README.md).
"$godot" --headless --path game res://server/main.tscn -- --dev &
game=$!
"$tmp/relay" &
relay=$!

# ShellCheck can't see that the EXIT trap below calls this.
# shellcheck disable=SC2329
stop() {
	kill "$game" "$relay" 2>/dev/null
	wait "$game" "$relay" 2>/dev/null
	rm -rf "$tmp" "$pidfile"
}
trap stop EXIT
trap 'exit 130' INT TERM

# macOS's bash has no `wait -n`, so check on both every half second.
while kill -0 "$game" 2>/dev/null && kill -0 "$relay" 2>/dev/null; do
	sleep 0.5
done
if kill -0 "$game" 2>/dev/null; then
	echo "dev.sh: the relay exited; stopping the game server" >&2
else
	echo "dev.sh: the game server exited; stopping the relay" >&2
fi
exit 1
