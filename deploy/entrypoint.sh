#!/usr/bin/env bash
# Runs the game server and the relay. When either exits, stops the other and
# exits too, so Docker's restart policy starts both again. Arguments go to
# the relay (compose.yaml passes the domain and origin).
set -u

# The relay's ports inside the container; compose.yaml maps 443 and 80 here.
# Unprivileged, so the container needs no extra capabilities.
https_port=8443
http_port=8080

stop() {
	local listed pids
	listed=$(jobs -p)
	[[ -n $listed ]] || return 0
	mapfile -t pids <<<"$listed"
	# The shell's own kill: the image has no kill program (procps isn't
	# installed), so `xargs kill` can't work. Errors are for a process
	# that has already exited.
	kill "${pids[@]}" 2>/dev/null
}
trap stop TERM INT

godot --headless --path /app/game -- --server &
relay -addr ":$https_port" -http ":$http_port" -static /app/web "$@" &

wait -n
code=$?
echo "entrypoint: a process exited with $code; stopping the other" >&2
stop
wait
exit "$code"
