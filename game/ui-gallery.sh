#!/usr/bin/env bash
# Renders every UI screen in the states listed in tools/ui_gallery/shots.gd
# to PNGs, plus contact_sheet.png with all of them captioned. Opens a
# window for a moment: a headless Godot draws nothing.
# Usage: ./ui-gallery.sh [out dir], by default the vault's "UI gallery"
# folder, whose PNGs the vault leaves out of its git. Worktrees don't have
# the notes symlink, so it's found through the main checkout.
cd "$(dirname "$0")" || exit 1
godot="${GODOT_BIN:-godot}"
if [ -n "$1" ]; then
	out="$1"
else
	main="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")"
	if [ ! -d "$main/notes" ]; then
		echo "ui-gallery: no notes/ in the main checkout ($main)" >&2
		exit 1
	fi
	out="$main/notes/2 How it works/UI gallery"
fi
mkdir -p "$out" || exit 1
out="$(cd "$out" && pwd)"
# Old shots of states since removed shouldn't linger.
rm -f "$out"/*.png "$out/shots.json"
# Newly added scripts aren't known to the project until it's imported.
"$godot" --headless --import > /dev/null 2>&1
# A script error stops ui_gallery.gd before it can quit, and Godot then
# runs until killed, so give up after this long. A run lasts a few
# seconds.
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
