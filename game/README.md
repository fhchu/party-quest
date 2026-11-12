# Client and game server

One Godot 4.7 project runs as both the browser client and the
server-authoritative game server. Gameplay values are in `sim/balance.json`
(restart the server after editing it).

```
net/               what both sides share to talk: RPC endpoint (net.gd),
                   wire format, transport base, network constants
sim/               the simulation (plain data, no nodes) and balance values
server/            lobby: seats, ready, town and match phases, timer;
                   server.gd wires connections to it; tcp_server_peer.gd
                   takes them; main.tscn starts it
client/            input, interpolation, drawing; ui/ holds the screens;
                   transports: WebTransport in a browser, TCP on desktop;
                   main.tscn starts it (the project's main scene)
util/options.gd    options from `-- --key=value` or the web query string
tools/ui_gallery/  draws every UI screen in fixed states to PNGs
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

`dev.sh` starts the game server with `--dev`, so the dev keys below
work.

It runs both until Ctrl+C, and stops both if either one exits. To run them
separately instead, in two terminals:

```bash
godot --headless --path game res://server/main.tscn -- --dev  # game server on :9081
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
game/run-tests.sh                                      # Godot: sim, client, transport, lobby
cd relay && go test ./...                              # the relay
```

Exit code 0 means everything passed. In the editor, the GdUnit4 panel runs
them too. The lobby tests run a real server and clients in one process.

## UI gallery

```bash
game/ui-gallery.sh
```

Draws every screen, arena included, in the states listed in
`tools/ui_gallery/shots.gd` to `build/ui-gallery/`: one PNG per state and
`contact_sheet.png` with all of them captioned. It opens a window for a moment, since a headless Godot
draws nothing. Add a shot with each new screen or state.

## Snapshot size

Snapshots have to fit one datagram. `./check.sh` ends with a line giving a
full lobby's snapshot size against that budget
(`tools/snapshot_size.gd`), and a test fails if it stops fitting. The
debug overlay shows the size of each snapshot as it arrives.

## Options

Desktop: `-- --key=value` after the command; web: `?key=value`. A bare key
means true. `util/options.gd` reads them for both sides.

| Option | Read by | Meaning |
|---|---|---|
| `dev` | both | client: the debug overlay, and F8 / F9 to end a match as a win / loss; game server: accepts those keys. Both need it |
| `port` | game server | port to listen on. Default: `PORT` from the environment, else 9081 |
| `bind` | game server | address to listen on. Default: `127.0.0.1` |
| `exit-when-empty` | game server | quit once nobody has held a seat for `EMPTY_EXIT_SEC` in `server/lobby.gd`; for the relay's launcher |
| `url` | client | server address. Default: for an `https` page, `/match` on the page's own host (the relay served it); for an `http` page, `https://<page host>:9080/match`; on desktop, `tcp://127.0.0.1:9081`, the game server |
| `lag` | client | simulated round-trip latency in ms, applied on this device |
| `jitter` | client | simulated hold-ups of up to N ms, a couple a second |
| `interp` | client | fixed interpolation delay in ms (default: adapts to the connection) |
| `bot` | client | readies up in town by hitting the READY dummy, then waits; random movement and attacks in a match |
| `drop-after` | client | close the connection once after N seconds, to test reconnecting |
| `quit-after` | client | quit after N seconds and print a `SMOKE` summary line |

## Play

Controls: WASD to move, Space to swing. Keyboard only for the MVP.

A lobby starts in town, where you're already playing. Hit the READY
dummy to toggle your ready. Once everyone connected is ready, the START
dummy turns green, and hitting it starts the match. In the match, killing
the dummy (3 hits) wins; touching it costs health; the timer (`match` in
`sim/balance.json`) running out is a loss; a dev key ends it either way.
The result shows for a few seconds, then everyone is back in town,
not ready. Someone joining mid-match waits until then.

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

- Cold load under ~5 s (`load` on the debug overlay), and a steady 60 fps (`fps`).
- Two tabs stay in sync with `?lag=100`.
- Turning Wi-Fi off and on (or sleeping the laptop) reconnects you as the
  same player.
