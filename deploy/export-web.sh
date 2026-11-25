#!/usr/bin/env bash
# Exports the web build to deploy/web for the image, every file replaced by
# its brotli-compressed copy (name.br): the relay serves only those
# (relay/static.go). Needs brotli (brew install brotli). Brotli's best level
# needs about a minute on the engine's .wasm.
#
# With no flags (usage below), it makes the deploy's build in deploy/web.
# --out DIR is from the repo root, or absolute.
set -euo pipefail
cd "$(dirname "$0")/.."
godot="${GODOT_BIN:-godot}"
usage="usage: export-web.sh [--out DIR] [--brotli-quality N] [--debug]"
out=deploy/web
quality=11
mode=release
while [ $# -gt 0 ]; do
	case "$1" in
		--out) [ $# -ge 2 ] || { echo "$usage" >&2; exit 2; }; out="$2"; shift 2 ;;
		--brotli-quality) [ $# -ge 2 ] || { echo "$usage" >&2; exit 2; }; quality="$2"; shift 2 ;;
		--debug) mode=debug; shift ;;
		*) echo "$usage" >&2; exit 2 ;;
	esac
done
out="$(cd "$(dirname "$out")" && pwd)/$(basename "$out")"

rm -rf "$out"
mkdir -p "$out"
"$godot" --headless --path game "--export-$mode" "Web" "$out/index.html"
# The engine inside the build is MIT and bundles other libraries; their
# notices go beside it, linked from the page (html/head_include in
# game/export_presets.cfg).
"$godot" --headless --path game -s res://tools/licenses.gd -- "$out/licenses.txt"
# The page shows the canvas a quarter turn clockwise while pqRotated is set,
# but the engine places presses as if it weren't turned. Its press code
# ships as plain text in the .js, so this has it ask the page's
# pqRotatedPosition instead, which sits beside the turn
# (game/client/web_shell.html; check.sh checks the names agree).
python3 - "$out/index.js" <<'EOF'
import sys
path = sys.argv[1]
find = "computePosition:function(evt,rect){const canvas=GodotConfig.canvas;"
rotated = "if(window.pqRotated){return window.pqRotatedPosition(evt,rect,canvas)}"
with open(path) as f:
	js = f.read()
if js.count(find) != 1:
	sys.exit(f"export-web.sh: {path} has {js.count(find)} copies of the engine's press code, want 1")
with open(path, "w") as f:
	f.write(js.replace(find, find + rotated))
EOF
# --rm drops each original once compressed. The copies keep the originals'
# dates, so the relay's If-Modified-Since answers stay right.
brotli --rm -q "$quality" "$out"/*
