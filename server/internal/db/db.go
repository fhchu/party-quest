// Package db opens the SQLite database and applies the embedded migrations.
package db

import (
	"context"
	"database/sql"
	"fmt"
	"net/url"

	"github.com/pressly/goose/v3"
	// Registers the "sqlite" driver: pure Go, so builds need no C compiler.
	_ "modernc.org/sqlite"

	"game/server/migrations"
)

// busyTimeoutMS is how long a statement waits for another process's write
// lock, such as an admin's sqlite3 shell, before failing. Untuned.
const busyTimeoutMS = 5000

// Open opens the database file at path, creating it if needed, and pings it,
// so a bad path fails at startup. Foreign keys are enforced, which SQLite
// leaves off by default.
func Open(ctx context.Context, path string) (*sql.DB, error) {
	q := url.Values{}
	q.Add("_pragma", "foreign_keys(1)")
	q.Add("_pragma", "journal_mode(WAL)")
	q.Add("_pragma", fmt.Sprintf("busy_timeout(%d)", busyTimeoutMS))
	sqlDB, err := sql.Open("sqlite", "file:"+path+"?"+q.Encode())
	if err != nil {
		return nil, fmt.Errorf("open database: %w", err)
	}
	// SQLite allows one writer at a time. With one connection, Go queues
	// every statement instead of SQLite failing the second writer.
	sqlDB.SetMaxOpenConns(1)
	if err := sqlDB.PingContext(ctx); err != nil {
		sqlDB.Close()
		return nil, fmt.Errorf("ping database: %w", err)
	}
	return sqlDB, nil
}

// Migrate applies any pending goose migrations from the migrations package.
func Migrate(ctx context.Context, sqlDB *sql.DB) error {
	provider, err := goose.NewProvider(goose.DialectSQLite3, sqlDB, migrations.FS)
	if err != nil {
		return fmt.Errorf("create migration provider: %w", err)
	}
	if _, err := provider.Up(ctx); err != nil {
		return fmt.Errorf("apply migrations: %w", err)
	}
	return nil
}
