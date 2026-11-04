#!/usr/bin/env bash
# Builds the game image on this Mac and starts it on the server. A 1 GB
# instance can run out of memory building it, so it's built here.
#
# Usage: deploy/deploy.sh user@host
# Needs here: Docker, Godot, deploy/.env (copy deploy/.env.example).
# Needs there: Docker Engine with the compose plugin, and the SSH user in the
# docker group.
set -euo pipefail
cd "$(dirname "$0")/.."
host="${1:?usage: deploy/deploy.sh user@host}"
if [ ! -f deploy/.env ]; then
	echo "deploy.sh: deploy/.env is missing; copy deploy/.env.example" >&2
	exit 1
fi

deploy/export-web.sh
docker build --platform linux/amd64 -f deploy/Dockerfile -t party-quest:latest .
docker save party-quest:latest | gzip | ssh "$host" 'gunzip | docker load'
ssh "$host" 'mkdir -p party-quest'
scp deploy/compose.yaml deploy/.env "$host:party-quest/"
ssh "$host" 'cd party-quest && docker compose up -d && docker image prune -f'
