---
trigger: glob
globs: "game/client/**, **/*.tscn, game/tools/ui_gallery/**, game/ui-gallery.sh"
paths:
  - "game/client/**"
  - "**/*.tscn"
  - "game/tools/ui_gallery/**"
  - "game/ui-gallery.sh"
---

# UI

The owner reviews UI as pictures, never as `.tscn` or `.tres` text.

- After changing anything on screen, run `game/ui-gallery.sh` and look at
  the shots in `game/build/ui_gallery/` (open `contact_sheet.png`)
  yourself before calling it done (checked: the `ui-shots-on-stop` hook).
  The script copies them into the vault itself.
  Fix what looks wrong; report design problems you notice.
- A new screen or state gets a shot in `game/tools/ui_gallery/shots.gd`.
- When describing a UI change to the owner, show the shots and say in
  words what's where and what changes between states.
- iPhone Safari runs WebTransport, and it's the main phone the game is
  built for.
- Touch controls work 1:1 with the mouse (`emulate_touch_from_mouse` is
  on): a click does what a tap does.
