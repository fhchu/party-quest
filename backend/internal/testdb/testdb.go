// Package testdb provides a throwaway, migrated SQLite database for tests.
package testdb

import (
	"context"
	"database/sql"
	"path/filepath"
	"testing"

	"game/backend/internal/db"
)

// New returns a migrated database in a file that lasts as long as the test.
func New(t *testing.T) *sql.DB {
	t.Helper()
	ctx := context.Background()
	sqlDB, err := db.Open(ctx, filepath.Join(t.TempDir(), "test.db"))
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	t.Cleanup(func() { sqlDB.Close() })
	if err := db.Migrate(ctx, sqlDB); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	return sqlDB
}
