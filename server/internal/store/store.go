// Package store holds every SQL statement the backend runs, so moving to
// another database means changing one package. Statements stick to SQL that
// Postgres also accepts.
package store

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	"game/server/items"
)

// timeLayout is how times are stored: UTC with milliseconds, always the same
// width, so text order is time order.
const timeLayout = "2006-01-02T15:04:05.000Z"

// Store runs the backend's statements against one database.
type Store struct {
	db *sql.DB
}

// New returns a Store for db.
func New(db *sql.DB) *Store {
	return &Store{db: db}
}

func formatTime(t time.Time) string {
	return t.UTC().Format(timeLayout)
}

// SyncItems makes the item table match all: it adds new items and updates
// names and disabled times. An item in the table but not in all is an error:
// ledger rows may point at it, so it can't be deleted, and items.json must
// keep it, disabled.
func (s *Store) SyncItems(ctx context.Context, all []items.Item) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()

	listed := map[string]bool{}
	for _, it := range all {
		listed[it.ID] = true
		var disabledAt *string
		if it.DisabledAt != nil {
			t := formatTime(*it.DisabledAt)
			disabledAt = &t
		}
		_, err := tx.ExecContext(ctx, `
			INSERT INTO item (id, name, disabled_at) VALUES ($1, $2, $3)
			ON CONFLICT (id) DO UPDATE SET name = excluded.name, disabled_at = excluded.disabled_at`,
			it.ID, it.Name, disabledAt)
		if err != nil {
			return fmt.Errorf("item %q: %w", it.ID, err)
		}
	}

	rows, err := tx.QueryContext(ctx, `SELECT id FROM item`)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return err
		}
		if !listed[id] {
			return fmt.Errorf("item %q is in the database but not in items.json; keep it there, disabled", id)
		}
	}
	if err := rows.Err(); err != nil {
		return err
	}
	return tx.Commit()
}
