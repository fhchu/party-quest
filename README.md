# Co-op game: backend and client

Go backend plus a Godot 4 web client for a small co-op Zelda-like. The backend
(saves, match results, stats) is the main project; the game generates the data.

## Layout

```
server/
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
client/            Godot client and authoritative game server (see client/README.md)
docker-compose.yml Postgres for local development
```

## First run

You need Go 1.25 or newer (the migration library requires it; with the default
`GOTOOLCHAIN=auto` the `go` command downloads it for you) and Docker.

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

## Notes

- The integration tests skip themselves if Docker isn't running, so a green
  `go test` with skips does not prove the schema tests passed. Run it with
  `go test -v ./...` and check that `TestDuplicateMatchIDIsRejected` actually ran.
- `AUTO_MIGRATE=true` applies migrations at startup. That is convenient with one
  instance; with several, run migrations as a separate deploy step.
- `/health` never touches the database, so a platform health check cannot
  restart the server over a database blip. `/ready` does check it.

## Next

The backend is paused while the client is proven out: first, the Godot
client and server-authoritative game server in desktop browsers (checklist in
`client/README.md`).
