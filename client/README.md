# Client and game server (Phase 0 spike)

One Godot 4.7 project runs as both the browser client and the
server-authoritative game server. Gameplay values in `sim/tuning.gd`
are placeholders.

```
main.gd            picks server or client from the options
net/               RPC endpoint (net.gd) and network constants
sim/               the simulation, plain data with no nodes; runs on the server
server/            room: sessions, reconnects, tick loop, snapshots
client/            input, interpolation, drawing, debug HUD
util/args.gd       options from `-- --key=value` or the web query string
```

## Run locally

```bash
godot --headless --path client -- --server             # game server on :9080
godot --path client                                    # a desktop client
godot --headless --path client -- --bot --lag=100      # a bot player
```

Client options (desktop: `-- --key=value`; web: `?key=value`):

| Option | Meaning |
|---|---|
| `url` | server address, default `ws://<page host>:9080` (desktop: `ws://127.0.0.1:9080`) |
| `lag` | simulated round-trip latency in ms, applied on this device |
| `interp` | interpolation delay in ms (default 100) |
| `bot` | random movement and attacks |
| `drop-after` | close the socket once after N seconds, to test reconnecting |
| `quit-after` | quit after N seconds and print a `SMOKE` summary line |

Controls: WASD to move, Space to swing. Keyboard only for the MVP.

## Server container

```bash
docker build --platform linux/amd64 -t party-quest-server client
docker run --rm -p 9080:9080 party-quest-server
```

Browsers on an `https://` page need `wss://`. Run a TLS proxy in front of the
server; by default the client expects it at `wss://<page host>/ws`.

## Web build

Needs the export templates once: Editor → Manage Export Templates →
Download 4.7.2. The Web preset is in `export_presets.cfg`, with Thread
Support off so the build needs no cross-origin isolation headers (for
itch.io).

- **Quick:** start the game server, then click **Run in Browser** in the
  editor. It exports and serves the game at `http://localhost:8060`; open
  more tabs there for more players. Click it again after changes ("Start
  HTTP Server" alone serves the previous build).
- **A build you keep:** Project → Export → Web to
  `client/build/web/index.html` (ignored by git), then
  `python3 -m http.server 8000 -d client/build/web` and open
  `http://localhost:8000`.

## Phase 0 checks (desktop Chrome; the MVP targets Chrome only)

- Cold load under ~5 s (`load` on the HUD), and a steady 60 fps (`fps`).
- Two tabs stay in sync with `?lag=100`.
- Turning Wi-Fi off and on (or sleeping the laptop) reconnects you as the
  same player.
