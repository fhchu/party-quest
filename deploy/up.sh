#!/usr/bin/env bash
# Starts the game on the server at one version: copies the Compose file and
# the domain there, writes the version and the secrets beside them as .env
# (so plain `docker compose` commands there work with no arguments), and
# runs `docker compose up -d`. Compose pulls the images from the registry if
# the server doesn't have that tag; deploy/deploy.sh loads the tag "local"
# first.
#
# Usage: deploy/up.sh user@host VERSION
# Needs here: each name in `secrets` below set in the environment. They go
# over SSH's input, never on a command line, where other users could see
# them. Needs there: Docker Engine with the compose plugin, and the SSH user
# in the docker group.
set -euo pipefail
cd "$(dirname "$0")"
host="${1:?usage: deploy/up.sh user@host VERSION}"
version="${2:?usage: deploy/up.sh user@host VERSION}"
# The version goes into a remote shell command and an image tag.
if [[ ! $version =~ ^[A-Za-z0-9._-]+$ ]]; then
	echo "up.sh: bad version: $version" >&2
	exit 1
fi

# Must match what deploy/compose.yaml reads and deploy/secrets.env.example
# lists.
secrets=(GAME_SERVER_TOKEN)
env_lines=""
for name in "${secrets[@]}"; do
	value="${!name:-}"
	if [[ -z $value || $value == *$'\n'* ]]; then
		echo "up.sh: set $name, on one line" >&2
		exit 1
	fi
	env_lines+="$name=$value"$'\n'
done

ssh "$host" 'mkdir -p party-quest'
scp compose.yaml domain.env "$host:party-quest/"
# The secrets arrive on the remote command's input; .env is readable only
# by the SSH user. The version expands here on purpose: it was checked
# above, so it is safe in the command.
# shellcheck disable=SC2029
printf '%s' "$env_lines" | ssh "$host" "set -euo pipefail
cd party-quest
umask 077
{ cat domain.env; cat; echo VERSION=$version; } > .env
docker compose up -d
# Only the running version stays; the registry keeps every other one.
docker image prune -a -f"
