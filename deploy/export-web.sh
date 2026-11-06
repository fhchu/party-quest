#!/usr/bin/env bash
# Exports the web build to deploy/web for the image, every file replaced by
# its brotli-compressed copy (name.br): the relay serves only those
# (relay/static.go). Needs brotli (brew install brotli). Brotli's best level
# takes about a minute on the engine's .wasm.
set -euo pipefail
cd "$(dirname "$0")/.."
godot="${GODOT_BIN:-godot}"
out="$PWD/deploy/web"

rm -rf "$out"
mkdir -p "$out"
"$godot" --headless --path game --export-release "Web" "$out/index.html"
# --rm drops each original once compressed. The copies keep the originals'
# dates, so the relay's If-Modified-Since answers stay right.
brotli --rm -q 11 "$out"/*
