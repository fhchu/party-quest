package db_test

import (
	"context"
	"errors"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"game/server/internal/db"
	"game/server/internal/testdb"
)

func insertMatch(pool *pgxpool.Pool, matchID uuid.UUID) error {
	_, err := pool.Exec(context.Background(), `
		INSERT INTO match (id, balance_version)
		VALUES ($1, 'v1')`, matchID)
	return err
}

func TestDuplicateMatchIDIsRejected(t *testing.T) {
	pool := testdb.New(t)
	matchID := uuid.New()

	if err := insertMatch(pool, matchID); err != nil {
		t.Fatalf("first insert: %v", err)
	}

	err := insertMatch(pool, matchID)
	var pgErr *pgconn.PgError
	if !errors.As(err, &pgErr) || pgErr.Code != "23505" {
		t.Fatalf("second insert error = %v, want unique violation (23505)", err)
	}
}

func TestInvalidOutcomeIsRejected(t *testing.T) {
	pool := testdb.New(t)

	_, err := pool.Exec(context.Background(), `
		INSERT INTO match (id, balance_version, status, outcome, ended_at)
		VALUES ($1, 'v1', 'completed', 'draw', now())`, uuid.New())
	var pgErr *pgconn.PgError
	if !errors.As(err, &pgErr) || pgErr.Code != "23514" {
		t.Fatalf("error = %v, want check violation (23514)", err)
	}
}

func TestMigrationsAreRepeatable(t *testing.T) {
	pool := testdb.New(t)
	if err := db.Migrate(context.Background(), pool); err != nil {
		t.Fatalf("second migrate: %v", err)
	}
}
