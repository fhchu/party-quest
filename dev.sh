#!/usr/bin/env bash
# Runs the game server and the relay together. Ctrl+C stops them; if either
# exits, the other is stopped too.
#
# `dev.sh --web` also exports the client once, at start, and serves it on
# the editor's Run in Browser port at /tmp_js_export.html (the page it
# opens), which stops with the rest. Run it on your machine, not wherever
# the game server is hosted.
#
# `dev.sh --lan` serves the client from the relay over HTTPS at this Mac's
# .local name instead, which stays put when its address changes, for a
# phone on the same network: a phone needs
# HTTPS for WebTransport. The certificate comes from mkcert (brew install
# mkcert), and the phone must trust mkcert's root once: AirDrop it
# rootCA.pem from `mkcert -CAROOT`, install the profile, then turn on full
# trust in Settings > General > About > Certificate Trust Settings.
set -u
cd "$(dirname "$0")" || exit 1
godot="${GODOT_BIN:-godot}"
web_port=8060
# The relay's own -addr default; check.sh checks they agree.
relay_port=9080
# Quick compression for --lan: seconds, where the best level takes a minute.
lan_brotli_quality=5

web=false
lan=false
case "${1:-}" in
	"") ;;
	--web) web=true ;;
	--lan) lan=true ;;
	*) echo "usage: dev.sh [--web | --lan]" >&2; exit 2 ;;
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

relay_args=()
if $lan; then
	name="$(scutil --get LocalHostName)" || { echo "dev.sh: this Mac has no .local name" >&2; rm -rf "$tmp"; exit 1; }
	# Lowercase, as a browser sends it in Origin, which the relay matches
	# exactly.
	host="$(echo "$name" | tr '[:upper:]' '[:lower:]').local"
	# Outside the repo; a reboot clears it, and a new one is trusted all the
	# same, since the phone trusts mkcert's root.
	certs="${TMPDIR:-/tmp}/party-quest-lan"
	if [ ! -f "$certs/$host.pem" ]; then
		mkdir -p "$certs"
		mkcert -cert-file "$certs/$host.pem" -key-file "$certs/$host-key.pem" "$host" \
			|| { rm -rf "$tmp"; exit 1; }
	fi
	deploy/export-web.sh --out "$tmp/lan-web" --brotli-quality "$lan_brotli_quality" --debug || { rm -rf "$tmp"; exit 1; }
	relay_args=(-cert "$certs/$host.pem" -key "$certs/$host-key.pem" -static "$tmp/lan-web"
		-origin "https://$host:$relay_port")
	echo "dev.sh: client at https://$host:$relay_port/"
fi

web_pid=""
if $web; then
	mkdir "$tmp/web"
	"$godot" --headless --path game --export-debug "Web" "$tmp/web/tmp_js_export.html" \
		|| { rm -rf "$tmp"; exit 1; }
	echo "dev.sh: client at http://localhost:$web_port/tmp_js_export.html"
	python3 -m http.server "$web_port" --bind 127.0.0.1 --directory "$tmp/web" &
	web_pid=$!
fi

"$godot" --headless --path game res://server/main.tscn &
game=$!
# macOS's bash calls an empty array unbound under set -u.
"$tmp/relay" ${relay_args[@]+"${relay_args[@]}"} &
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

# macOS's bash has no `wait -n`, so check on each every half second.
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
