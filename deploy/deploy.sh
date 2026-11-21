#!/usr/bin/env bash
# Builds the game and backend images on this Mac, sends them to the server
# over SSH and starts them there. The fallback for
# .github/workflows/release.yml, which builds, pushes and deploys a version
# tag from GitHub.
#
# Usage: deploy/deploy.sh user@host
# Needs here: Docker, Godot, brotli, and deploy/secrets.env (from
# deploy/secrets.env.example). Needs there: see deploy/up.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
host="${1:?usage: deploy/deploy.sh user@host}"
# Must match the image names in deploy/compose.yaml.
image=ghcr.io/fhchu/party-quest:local
backend_image=ghcr.io/fhchu/party-quest-backend:local

# Exported, for up.sh.
set -a
# shellcheck source=/dev/null
. deploy/secrets.env
set +a

deploy/export-web.sh
docker build --platform linux/amd64 -f deploy/Dockerfile -t "$image" .
docker build --platform linux/amd64 -f deploy/backend.Dockerfile -t "$backend_image" .
docker save "$image" "$backend_image" | gzip | ssh "$host" 'gunzip | docker load'
deploy/up.sh "$host" local
