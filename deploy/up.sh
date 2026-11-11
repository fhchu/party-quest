#!/usr/bin/env bash
# Starts the game on the server at one version: copies the Compose file and
# the domain there, writes the version beside them as .env (so plain
# `docker compose` commands there work with no arguments), and runs
# `docker compose up -d`. Compose pulls the image from the registry if the
# server doesn't have that tag; deploy/deploy.sh loads the tag "local" first.
#
# Usage: deploy/up.sh user@host VERSION
# Needs there: Docker Engine with the compose plugin, and the SSH user in the
# docker group.
set -euo pipefail
cd "$(dirname "$0")"
host="${1:?usage: deploy/up.sh user@host VERSION}"
version="${2:?usage: deploy/up.sh user@host VERSION}"
# The version goes into a remote shell command and an image tag.
if [[ ! $version =~ ^[A-Za-z0-9._-]+$ ]]; then
	echo "up.sh: bad version: $version" >&2
	exit 1
fi

ssh "$host" 'mkdir -p party-quest'
scp compose.yaml domain.env "$host:party-quest/"
ssh "$host" bash -s -- "$version" <<'REMOTE'
set -euo pipefail
cd party-quest
{ cat domain.env; echo "VERSION=$1"; } > .env
docker compose up -d
# Only the running version stays; the registry keeps every other one.
docker image prune -a -f
REMOTE
