#!/usr/bin/env bash
# Renders every UI screen in the states listed in tools/ui_gallery/shots.gd
# to PNGs, plus contact_sheet.png with all of them captioned. Opens a
# window for a moment: a headless Godot draws nothing.
# Usage: ./ui-gallery.sh [out dir], by default build/ui-gallery.
cd "$(dirname "$0")" || exit 1
godot="${GODOT_BIN:-godot}"
out="${1:-build/ui-gallery}"
mkdir -p "$out" || exit 1
out="$(cd "$out" && pwd)"
# Old shots of states since removed shouldn't linger.
rm -f "$out"/*.png "$out/shots.json"
# Newly added scripts aren't known to the project until it's imported.
"$godot" --headless --import > /dev/null 2>&1
# A script error stops ui_gallery.gd before it can quit, and Godot then
# runs until killed, so give up after this long. Untuned: a run takes a
# few seconds.
timeout_sec=60
"$godot" --path . -s res://tools/ui_gallery/ui_gallery.gd -- "$out" &
pid=$!
waited=0
while kill -0 "$pid" 2> /dev/null; do
	if [ "$waited" -ge "$timeout_sec" ]; then
		kill "$pid"
		echo "ui-gallery: no result after $timeout_sec s; look for a script error above" >&2
		exit 1
	fi
	sleep 1
	waited=$((waited + 1))
done
wait "$pid"
