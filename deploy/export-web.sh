#!/usr/bin/env bash
# Exports the web build to deploy/web for the image, every file replaced by
# its brotli-compressed copy (name.br): the relay serves only those
# (relay/static.go). Needs brotli (brew install brotli). Brotli's best level
# takes about a minute on the engine's .wasm.
#
# usage: export-web.sh [out-dir] [brotli-quality] [release|debug]
# The defaults make the deploy's build. dev.sh --lan asks for a quick debug
# build in a folder of its own. out-dir is from the repo root, or absolute.
set -euo pipefail
cd "$(dirname "$0")/.."
godot="${GODOT_BIN:-godot}"
out="${1:-deploy/web}"
quality="${2:-11}"
mode="${3:-release}"
case "$mode" in
	release | debug) ;;
	*) echo "export-web.sh: want release or debug, got $mode" >&2; exit 2 ;;
esac
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
