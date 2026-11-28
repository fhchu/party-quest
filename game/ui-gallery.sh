#!/usr/bin/env bash
# Renders every UI screen in the states listed in tools/ui_gallery/shots.gd
# to PNGs, plus contact_sheet.png with all of them captioned. Opens a
# window for a moment: a headless Godot draws nothing.
# Usage: ./ui-gallery.sh [out dir], by default build/ui_gallery/, which git
# ignores. A default run then copies the shots into the vault's "UI
# gallery" folder, whose PNGs the vault leaves out of its git, when the
# main checkout has the vault's notes symlink; worktrees don't have it, so
# it's found through the main checkout.
cd "$(dirname "$0")" || exit 1
godot="${GODOT_BIN:-godot}"
DEFAULT_OUT=build/ui_gallery
VAULT_GALLERY="2 How it works/UI gallery"
out="${1:-$DEFAULT_OUT}"
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
wait "$pid" || exit
# Shots sent to an out dir of the caller's choosing stay there.
[ -z "${1:-}" ] || exit 0
main="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")"
[ -d "$main/notes" ] || exit 0
vault="$main/notes/$VAULT_GALLERY"
mkdir -p "$vault" || exit 1
rm -f "$vault"/*.png "$vault/shots.json"
cp "$out"/*.png "$out/shots.json" "$vault"/ && echo "ui-gallery: copied to the vault's $VAULT_GALLERY"
