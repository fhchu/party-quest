---
paths:
  - "game/client/**"
  - "**/*.tscn"
  - "game/tools/ui_gallery/**"
  - "game/ui-gallery.sh"
---

# UI

The owner reviews UI as pictures, never as `.tscn` or `.tres` text.

- After changing anything on screen, run `game/ui-gallery.sh` and look at
  the shots in the vault's `2 How it works/UI gallery/` (open
  `contact_sheet.png`) yourself before calling it done.
  Fix what looks wrong; report design problems you notice.
- A new screen or state gets a shot in `game/tools/ui_gallery/shots.gd`.
- When describing a UI change to the owner, show the shots and say in
  words what's where and what changes between states.
- iPhone Safari runs WebTransport, and it's the main phone the game is
  built for.
