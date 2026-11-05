# Party Quest

An in-progress co-op action game for up to four players in the browser. Try it in Chrome
at [lelize.com](https://lelize.com) (placeholder domain).

## How it's built

The game runs on a headless Godot server hosted on AWS Lightsail. Browser clients only send inputs and render the game. Matches are server-authoritative for anti-cheat and data validity. A Go backend on Postgres stores match results for analytics and game balance.

Match traffic goes over WebTransport on UDP so packet loss doesn't stall the game like it does over TCP. Godot can't serve WebTransport, so a small Go relay sits in front of the game server.

All code is written by Claude Code, but I make every design decision and review every change.

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
deploy/            the hosted build: image, Compose file, deploy script
```

### Checks

`./check.sh` runs the linters in parallel, then, if they pass, the tests in
parallel. It needs [golangci-lint](https://golangci-lint.run/),
[gdstyle](https://github.com/atelico/gdstyle),
[ShellCheck](https://www.shellcheck.net/) and
[gitleaks](https://github.com/gitleaks/gitleaks):

```bash
brew install golangci-lint shellcheck gitleaks
# gdstyle: download the binary for your platform from its releases page
```

Linter settings are in `.golangci.yml` and `game/gdstyle.toml`.

GitHub Actions runs the same script on every pull request and every push
to `main` (`.github/workflows/check.yml`, which pins each tool's version).

### The game

See [game/README.md](game/README.md): start the game server and the
relay with `./dev.sh`, then Run in Browser from the Godot editor (desktop
Chrome).

### Hosting

The game runs on one server with Docker. `deploy/deploy.sh user@host`
builds the image on your machine, copies it over SSH and starts it. Copy
`deploy/.env.example` to `deploy/.env` first and set the domain.

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
