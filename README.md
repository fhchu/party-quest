# Party Quest

An online co-op action game for 1–4 players that runs in the browser. Join a
friend's room with a code and play together in real time. Each match also
records how people play, so balance changes can be based on data.

There's no public link to play yet. It runs locally (see below).

## How it's built

- A Godot 4.7 client and a headless game server share one simulation. The
  server runs the game at 30 Hz; clients send inputs and draw what comes back.
- Match traffic goes over WebTransport (UDP) through a small Go relay.
  Snapshots are packed to fit in one datagram.
- A Go and Postgres backend stores accounts, match results and stats.
- Regression tests run a real server and real clients over the real network
  code. The simulation is deterministic, and a test checks that too.
- Written with Claude Code. I make the design calls and review every change.

## Next

Enemies, a boss and full runs, with match data going to the stats backend.

---

## Running it

### Layout

```
game/              Godot project: browser client and authoritative game server (see game/README.md)
relay/             WebTransport relay between browsers and the game server (Go)
server/            backend HTTP API (Go)
  cmd/api/         HTTP API entrypoint
  internal/
    auth/          anonymous bearer tokens
    config/        env-var configuration
    db/            pgx pool and goose migrations
    httpapi/       routing and /health, /ready
    httpjson/      shared JSON request/response helpers
    matches/       POST /matches (idempotent on match_id)
    players/       POST /players, GET /profile, PUT /profile/data
    stats/         GET /stats/characters, GET /stats/items
    testdb/        throwaway Postgres for integration tests
  migrations/      SQL migrations (embedded into the binary)
docker-compose.yml Postgres for local development
dev.sh             runs the game server and the relay together
check.sh           runs every linter, then every test suite
```

### Checks

`./check.sh` runs the linters in parallel, then, if they pass, the tests in
parallel. It needs [golangci-lint](https://golangci-lint.run/),
[gdstyle](https://github.com/atelico/gdstyle) and
[ShellCheck](https://www.shellcheck.net/):

```bash
brew install golangci-lint shellcheck
# gdstyle: download the binary for your platform from its releases page
```

Linter settings are in `.golangci.yml` and `game/gdstyle.toml`.

### The game

See [game/README.md](game/README.md): start the game server and the
relay with `./dev.sh`, then Run in Browser from the Godot editor (desktop
Chrome).

### The backend

You need Go 1.26 or newer (with the default `GOTOOLCHAIN=auto`, the `go`
command downloads it for you) and Docker.

```bash
docker compose up -d                 # Postgres on localhost:5432

cd server
go mod tidy                          # resolves dependencies and writes go.sum
go vet ./...
go test ./...                        # integration tests start their own Postgres

cp .env.example .env
export $(grep -v '^#' .env | xargs)  # or set the variables your own way
go run ./cmd/api

curl localhost:8080/health           # {"status":"ok"}
curl localhost:8080/ready            # {"status":"ready"} once the DB is reachable
```

Notes:
- The integration tests skip themselves if Docker isn't running, so a green
  `go test` with skips does not prove the schema tests passed. Run it with
  `go test -v ./...` and check that `TestDuplicateMatchIDIsRejected` actually ran.
- `AUTO_MIGRATE=true` applies migrations at startup. That is convenient with one
  instance; with several, run migrations as a separate deploy step.
- `/health` never touches the database, so a platform health check cannot
  restart the server over a database blip. `/ready` does check it.
