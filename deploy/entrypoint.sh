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

# In the container's own files, which a restart keeps and a deploy's new
# container doesn't. The line must match the restart alert in
# deploy/grafana/alerts.json and server/cmd/api/health.go.
start_marker=/tmp/game-started
if [[ -e $start_marker ]]; then
	echo "entrypoint: restarted in the same container: the last start exited" >&2
else
	: >"$start_marker"
fi

godot --headless --path /app/game res://server/main.tscn &
relay -addr ":$https_port" -http ":$http_port" -static /app/web "$@" &

wait -n
code=$?
echo "entrypoint: a process exited with $code; stopping the other" >&2
stop
wait
exit "$code"
