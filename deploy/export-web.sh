#!/usr/bin/env bash
# Exports the web build to deploy/web for the image, plus a gzipped copy of each file,
# which the relay sends to browsers that accept gzip (relay/static.go).
set -euo pipefail
cd "$(dirname "$0")/.."
godot="${GODOT_BIN:-godot}"
out="$PWD/deploy/web"

rm -rf "$out"
mkdir -p "$out"
"$godot" --headless --path game --export-release "Web" "$out/index.html"
# -k keeps the originals, for browsers without gzip; the copies keep their
# dates, so the relay's If-Modified-Since answers stay right.
gzip -k -9 "$out"/*.html "$out"/*.js "$out"/*.wasm "$out"/*.pck
