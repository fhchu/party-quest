#!/usr/bin/env bash
# Builds the game and backend images on this Mac, sends them to the server
# over SSH and starts them there. The fallback for
# .github/workflows/release.yml, which builds, pushes and deploys a version
# tag from GitHub.
#
# Usage: deploy/deploy.sh user@host, with a version tag on HEAD.
# Needs here: Docker, Godot, brotli, and deploy/secrets.env (from
# deploy/secrets.env.example). Needs there: see deploy/up.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
host="${1:?usage: deploy/deploy.sh user@host}"
# shellcheck source=/dev/null
. deploy/build.env

# Exported, for up.sh.
set -a
# shellcheck source=/dev/null
. deploy/secrets.env
set +a

# The build ID is the tag on HEAD, as in a release, so every deploy turns
# away tabs from the one before.
build_id=$(git describe --tags --exact-match HEAD) || {
	echo "deploy: HEAD has no tag; tag it (like v1.2.3) and run again" >&2
	exit 1
}
# Stamping edits project.godot in this checkout; put it back afterwards.
project_backup=$(mktemp)
cp game/project.godot "$project_backup"
trap 'mv "$project_backup" game/project.godot' EXIT
deploy/stamp-build.sh "$build_id"

deploy/export-web.sh
docker build --platform linux/amd64 -f deploy/Dockerfile \
	--build-arg GO_VERSION="$GO_VERSION" --build-arg GODOT_VERSION="$GODOT_VERSION" -t "$GAME_IMAGE:local" .
docker build --platform linux/amd64 -f deploy/backend.Dockerfile \
	--build-arg GO_VERSION="$GO_VERSION" -t "$BACKEND_IMAGE:local" .
docker save "$GAME_IMAGE:local" "$BACKEND_IMAGE:local" | gzip | ssh "$host" 'gunzip | docker load'
deploy/up.sh "$host" local
