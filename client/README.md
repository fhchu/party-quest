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

From the repo root, in two terminals:

```bash
godot --headless --path client -- --server             # game server on :9081
cd relay && go run .                                   # relay on :9080
```

Then:

```bash
godot --path client                                    # a desktop client
godot --headless --path client -- --bot --lag=100      # a bot player
```

Without `-cert`/`-key` the relay makes a self-signed certificate. A page
served over plain `http://` (Run in Browser) fetches its hash from
`http://<relay>/cert-hash` and trusts it; Chrome allows that only for
certificates valid under 14 days, so restart the relay every 10 days.

## Tests

```bash
client/run-tests.sh                                    # Godot: sim, client, transport, room
cd relay && go test ./...                              # the relay
```

Exit code 0 means everything passed. In the editor, the GdUnit4 panel runs
them too. The room tests run a real server and clients in one process.

Client options (desktop: `-- --key=value`; web: `?key=value`):

| Option | Meaning |
|---|---|
| `url` | server address, default `https://<page host>:9080/match`, the relay (desktop: `tcp://127.0.0.1:9081`, the game server) |
| `lag` | simulated round-trip latency in ms, applied on this device |
| `jitter` | simulated hold-ups of up to N ms, a couple a second |
| `interp` | fixed interpolation delay in ms (default: adapts to the connection) |
| `bot` | random movement and attacks |
| `drop-after` | close the connection once after N seconds, to test reconnecting |
| `quit-after` | quit after N seconds and print a `SMOKE` summary line |

Controls: WASD to move, Space to swing. Keyboard only for the MVP.

## Server container

```bash
docker network create pq
docker build --platform linux/amd64 -t party-quest-server client
docker run --rm --network pq --name game party-quest-server
docker build -t party-quest-relay relay
docker run --rm --network pq -p 9080:9080/udp -p 9080:9080/tcp party-quest-relay -game game:9081
```

The relay needs UDP port 9080 open to players, so an HTTP-only tunnel or
proxy can't carry it. For a page served over `https://`, give the relay a
real certificate (`-cert`, `-key`) for its domain.

## Web build

Needs the export templates once: Editor → Manage Export Templates →
Download 4.7.2. The Web preset is in `export_presets.cfg`, with Thread
Support off so the build needs no cross-origin isolation headers (for
itch.io).

- **Quick:** start the game server and the relay, then click **Run in Browser** in the
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
