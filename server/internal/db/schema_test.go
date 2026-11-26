package db_test

import (
	"context"
	"database/sql"
	"errors"
	"testing"

	"modernc.org/sqlite"
	sqlite3 "modernc.org/sqlite/lib"

	"game/server/internal/db"
	"game/server/internal/testdb"
)

const (
	runID    = "0192f6a8-0000-7000-8000-000000000001"
	playerID = "0192f6a8-0000-7000-8000-000000000002"
	itemID   = "gold"
	start    = "2026-11-17T21:00:00.000Z"
	end      = "2026-11-17T21:08:00.000Z"
)

func exec(t *testing.T, sqlDB *sql.DB, query string, args ...any) error {
	t.Helper()
	_, err := sqlDB.ExecContext(context.Background(), query, args...)
	return err
}

func insertRun(t *testing.T, sqlDB *sql.DB, id, outcome, startedAt, endedAt string) error {
	t.Helper()
	return exec(t, sqlDB, `
		INSERT INTO run (id, outcome, started_at, ended_at, received_at)
		VALUES ($1, $2, $3, $4, $4)`, id, outcome, startedAt, endedAt)
}

func insertLedger(t *testing.T, sqlDB *sql.DB, player string, amount int, reason string, run any) error {
	t.Helper()
	return exec(t, sqlDB, `
		INSERT INTO ledger (player_id, item_id, amount, reason, run_id, created_at)
		VALUES ($1, $2, $3, $4, $5, $6)`, player, itemID, amount, reason, run, end)
}

// withPlayerRunAndItem adds one of each, for rows that point at them.
func withPlayerRunAndItem(t *testing.T) *sql.DB {
	t.Helper()
	sqlDB := testdb.New(t)
	for _, err := range []error{
		exec(t, sqlDB, `INSERT INTO player (id, created_at) VALUES ($1, $2)`, playerID, start),
		exec(t, sqlDB, `INSERT INTO item (id, name) VALUES ($1, 'Gold')`, itemID),
		insertRun(t, sqlDB, runID, "won", start, end),
	} {
		if err != nil {
			t.Fatalf("setup: %v", err)
		}
	}
	return sqlDB
}

func wantCode(t *testing.T, err error, code int) {
	t.Helper()
	var se *sqlite.Error
	if !errors.As(err, &se) || se.Code() != code {
		t.Fatalf("error = %v, want SQLite code %d", err, code)
	}
}

func TestDuplicateRunIDIsRejected(t *testing.T) {
	sqlDB := withPlayerRunAndItem(t)
	wantCode(t, insertRun(t, sqlDB, runID, "lost", start, end), sqlite3.SQLITE_CONSTRAINT_PRIMARYKEY)
}

func TestEveryOutcomeIsAccepted(t *testing.T) {
	sqlDB := testdb.New(t)
	for _, outcome := range []string{"won", "lost", "abandoned"} {
		if err := insertRun(t, sqlDB, "run-"+outcome, outcome, start, end); err != nil {
			t.Errorf("outcome %q: %v", outcome, err)
		}
	}
}

func TestUnknownOutcomeIsRejected(t *testing.T) {
	sqlDB := testdb.New(t)
	wantCode(t, insertRun(t, sqlDB, runID, "draw", start, end), sqlite3.SQLITE_CONSTRAINT_CHECK)
}

func TestRunEndingBeforeItStartsIsRejected(t *testing.T) {
	sqlDB := testdb.New(t)
	wantCode(t, insertRun(t, sqlDB, runID, "won", end, start), sqlite3.SQLITE_CONSTRAINT_CHECK)
}

func TestLedgerRowForUnknownPlayerIsRejected(t *testing.T) {
	sqlDB := withPlayerRunAndItem(t)
	err := insertLedger(t, sqlDB, "no-such-player", 1, "run", runID)
	wantCode(t, err, sqlite3.SQLITE_CONSTRAINT_FOREIGNKEY)
}

func TestRunLedgerRowNeedsARun(t *testing.T) {
	sqlDB := withPlayerRunAndItem(t)
	wantCode(t, insertLedger(t, sqlDB, playerID, 1, "run", nil), sqlite3.SQLITE_CONSTRAINT_CHECK)
}

func TestRunPaysAPlayerOneRowPerItem(t *testing.T) {
	sqlDB := withPlayerRunAndItem(t)
	if err := insertLedger(t, sqlDB, playerID, 1, "run", runID); err != nil {
		t.Fatalf("first row: %v", err)
	}
	wantCode(t, insertLedger(t, sqlDB, playerID, 1, "run", runID), sqlite3.SQLITE_CONSTRAINT_UNIQUE)
}

func TestZeroAmountIsRejected(t *testing.T) {
	sqlDB := withPlayerRunAndItem(t)
	wantCode(t, insertLedger(t, sqlDB, playerID, 0, "run", runID), sqlite3.SQLITE_CONSTRAINT_CHECK)
}

func TestInventoryCountMayBeNegative(t *testing.T) {
	sqlDB := withPlayerRunAndItem(t)
	err := exec(t, sqlDB, `
		INSERT INTO inventory (player_id, item_id, count) VALUES ($1, $2, -3)`, playerID, itemID)
	if err != nil {
		t.Fatalf("negative count: %v", err)
	}
}

func TestMigrationsAreRepeatable(t *testing.T) {
	sqlDB := testdb.New(t)
	if err := db.Migrate(context.Background(), sqlDB); err != nil {
		t.Fatalf("second migrate: %v", err)
	}
}
