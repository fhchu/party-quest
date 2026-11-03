#!/usr/bin/env bash
# Runs the game server (:9081) and the relay (:9080) together. Ctrl+C stops
# both; if either exits, the other is stopped too.
set -u
cd "$(dirname "$0")"
godot="${GODOT_BIN:-godot}"

# Built, not `go run`: stopping `go run` can leave its relay running.
tmp="$(mktemp -d)"
(cd relay && go build -o "$tmp/relay" .) || exit 1

"$godot" --headless --path client -- --server &
game=$!
"$tmp/relay" &
relay=$!

stop() {
	kill "$game" "$relay" 2>/dev/null
	wait "$game" "$relay" 2>/dev/null
	rm -rf "$tmp"
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
