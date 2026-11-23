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
# The engine inside the build is MIT and bundles other libraries; their
# notices go beside it, linked from the page (html/head_include in
# game/export_presets.cfg).
"$godot" --headless --path game -s res://tools/licenses.gd -- "$out/licenses.txt"
# The page shows the canvas a quarter turn clockwise while pqRotated is set
# (game/client/web_shell.html; check.sh checks the name agrees), but the
# engine places presses as if it weren't turned. Its press code ships as
# plain text in the .js, so this places them on the turned canvas instead:
# across the canvas is down the page, and down the canvas is right to left.
python3 - "$out/index.js" <<'EOF'
import sys
path = sys.argv[1]
find = "computePosition:function(evt,rect){const canvas=GodotConfig.canvas;"
rotated = ("if(window.pqRotated){return["
		"(evt.clientY-rect.y)*canvas.width/rect.height,"
		"(rect.x+rect.width-evt.clientX)*canvas.height/rect.width]}")
with open(path) as f:
	js = f.read()
if js.count(find) != 1:
	sys.exit(f"export-web.sh: {path} has {js.count(find)} copies of the engine's press code, want 1")
with open(path, "w") as f:
	f.write(js.replace(find, find + rotated))
EOF
# --rm drops each original once compressed. The copies keep the originals'
# dates, so the relay's If-Modified-Since answers stay right.
brotli --rm -q 11 "$out"/*
