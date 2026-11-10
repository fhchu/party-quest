#!/usr/bin/env bash
# Builds the game image on this Mac, sends it to the server over SSH and
# starts it there. The fallback for .github/workflows/release.yml, which
# builds, pushes and deploys a version tag from GitHub.
#
# Usage: deploy/deploy.sh user@host
# Needs here: Docker, Godot, brotli. Needs there: see deploy/up.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
host="${1:?usage: deploy/deploy.sh user@host}"
# Must match the image name in deploy/compose.yaml.
image=ghcr.io/fhchu/party-quest:local

deploy/export-web.sh
docker build --platform linux/amd64 -f deploy/Dockerfile -t "$image" .
docker save "$image" | gzip | ssh "$host" 'gunzip | docker load'
deploy/up.sh "$host" local
