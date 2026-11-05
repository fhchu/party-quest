# Client and game server

One Godot 4.7 project runs as both the browser client and the
server-authoritative game server. Gameplay values are in `sim/balance.json`
(restart the server after editing it).

```
main.gd            picks server or client from the options
net/               RPC endpoint (net.gd), match transports, network constants
sim/               the simulation (plain data, no nodes) and balance values
server/            room: sessions, reconnects, tick loop, snapshots
client/            input, interpolation, drawing, debug HUD
util/args.gd       options from `-- --key=value` or the web query string
tests/             GdUnit4 tests (addons/gdUnit4 is the test framework)
```

## How match traffic flows

```
browser ──WebTransport (UDP)──▶ relay (Go, ../relay) ──TCP──▶ game server
desktop bot / test ─────────────────────────────────TCP──▶ game server
```

Godot can't serve WebTransport, so the relay does, on :9080, and opens one
local TCP connection to the game server (:9081) per player. Reliable
messages share one stream; inputs and snapshots go as datagrams, so a lost
one never holds up the rest. Everything outside a match will be plain HTTPS.

## Run locally

From the repo root:

```bash
./dev.sh                                               # game server on :9081, relay on :9080
```

It runs both until Ctrl+C, and stops both if either one exits. To run them
separately instead, in two terminals:

```bash
godot --headless --path game -- --server               # game server on :9081
cd relay && go run .                                   # relay on :9080
```

Then:

```bash
godot --path game                                      # a desktop client
godot --headless --path game -- --bot --lag=100        # a bot player
```

Without `-cert`/`-key` the relay makes a self-signed certificate. A page
served over plain `http://` (Run in Browser) fetches its hash from
`http://<relay>/cert-hash` and trusts it; Chrome allows that only for
certificates valid under 14 days, so restart the relay every 10 days.

## Tests

```bash
game/run-tests.sh                                      # Godot: sim, client, transport, room
cd relay && go test ./...                              # the relay
```

Exit code 0 means everything passed. In the editor, the GdUnit4 panel runs
them too. The room tests run a real server and clients in one process.

Game server options: `port`, `bind`, and `load-dummies` (wandering
load-test dummies).

Client options (desktop: `-- --key=value`; web: `?key=value`):

| Option | Meaning |
|---|---|
| `url` | server address. Default: for an `https` page, `/match` on the page's own host (the relay served it); for an `http` page, `https://<page host>:9080/match`; on desktop, `tcp://127.0.0.1:9081`, the game server |
| `lag` | simulated round-trip latency in ms, applied on this device |
| `jitter` | simulated hold-ups of up to N ms, a couple a second |
| `interp` | fixed interpolation delay in ms (default: adapts to the connection) |
| `bot` | random movement and attacks |
| `drop-after` | close the connection once after N seconds, to test reconnecting |
| `quit-after` | quit after N seconds and print a `SMOKE` summary line |

Controls: WASD to move, Space to swing. Keyboard only for the MVP.

## Hosted

`deploy/` at the repo root builds one image with the game server, the
relay and the web export, and runs it with Docker Compose. The relay
serves the page over HTTPS and match traffic on UDP 443, with a Let's
Encrypt certificate it renews itself.

## Web build

Needs the export templates once: Editor → Manage Export Templates →
Download 4.7.2. The Web preset is in `export_presets.cfg`, with Thread
Support off so the build needs no cross-origin isolation headers (for
itch.io).

- **Quick:** start the game server and the relay, then click **Run in Browser** in the
  editor. It exports and serves the game at `http://localhost:8060`; open
  more tabs there for more players. Click it again after changes ("Start
  HTTP Server" alone serves the previous build).
- **The release build, as hosted:** `deploy/export-web.sh` (writes
  `deploy/web/`, ignored by git), then
  `cd relay && go run . -static ../deploy/web` and open
  `http://127.0.0.1:9080`. Stop `dev.sh`'s relay first, or run this one
  on other ports with `-addr` and `?url=`.

## Phase 0 checks (desktop Chrome; the MVP targets Chrome only)

- Cold load under ~5 s (`load` on the HUD), and a steady 60 fps (`fps`).
- Two tabs stay in sync with `?lag=100`.
- Turning Wi-Fi off and on (or sleeping the laptop) reconnects you as the
  same player.
