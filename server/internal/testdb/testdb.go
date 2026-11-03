// Package testdb provides a throwaway, migrated Postgres for integration tests.
package testdb

import (
	"context"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/modules/postgres"

	"game/server/internal/db"
)

// postgresImage must match the postgres service in docker-compose.yml, so
// tests run against the same version as development.
const postgresImage = "postgres:18"

// New starts a Postgres container for the duration of the test and returns a
// pool connected to it. It skips the test if Docker is unavailable.
func New(t *testing.T) *pgxpool.Pool {
	t.Helper()
	ctx := context.Background()

	ctr, err := postgres.Run(ctx, postgresImage,
		postgres.WithDatabase("game"),
		postgres.WithUsername("game"),
		postgres.WithPassword("game"),
		postgres.BasicWaitStrategies(),
	)
	testcontainers.CleanupContainer(t, ctr)
	if err != nil {
		t.Skipf("cannot start Postgres container (is Docker running?): %v", err)
	}

	url, err := ctr.ConnectionString(ctx, "sslmode=disable")
	if err != nil {
		t.Fatalf("connection string: %v", err)
	}
	pool, err := db.Connect(ctx, url)
	if err != nil {
		t.Fatalf("connect: %v", err)
	}
	t.Cleanup(pool.Close)

	if err := db.Migrate(ctx, pool); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	return pool
}
