# Spike notes

Goal: retire the biggest risks before building the real game.

## Setup tested

- Godot 4 web export, uploaded to itch.io as an HTML project.
- Go WebSocket relay (rooms by query parameter) using github.com/coder/websocket.
- Public HTTPS/WSS via a Cloudflare quick tunnel to the laptop.

## Results

- Two desktop browsers on the itch page synced positions through the relay.
- The Godot window's text box (used to type the tunnel host) could not be pasted
  into or edited on an iPhone, so phone connectivity is still unverified.

## Known limitations of the spike

- Quick-tunnel URLs change on every run, hence the typed-host workaround.
- The relay skipped the WebSocket origin check (`InsecureSkipVerify`) and CORS was
  `*`. Both must be locked down to the real itch/site origins. Read the `Origin`
  header the itch iframe actually sends before writing the allowlist.
- Positions were sent every frame; the real game should send about 20 Hz and
  interpolate.

## Open items

- Retest on iPhone with a stable, hardcoded host once deployed.
- Decide how the host-authoritative client reports match results (host-only
  submission vs every player submitting and the server cross-checking).
