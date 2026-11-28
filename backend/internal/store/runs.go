package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"maps"
	"slices"
	"time"

	"github.com/google/uuid"
)

// ErrUnknownItem and ErrDisabledItem mean a run named an item the item table
// lacks or has retired. The run isn't stored.
var (
	ErrUnknownItem  = errors.New("unknown item")
	ErrDisabledItem = errors.New("disabled item")
)

// firebase is player_login.provider for Firebase UIDs.
const firebase = "firebase"

// Run is a finished run, as the game server reports it.
type Run struct {
	ID        string
	Outcome   string
	StartedAt time.Time
	EndedAt   time.Time
	Earners   []Earner
}

// Earner is one player's net item changes in a run.
type Earner struct {
	FirebaseUID string
	// Items maps an item ID to its net change, never 0.
	Items map[string]int64
}

// RecordRun stores the run and applies each earner's items in one
// transaction. If the run ID is already stored it changes nothing and
// reports created=false, so a retried submission pays once. An earner seen
// for the first time gets a player.
func (s *Store) RecordRun(ctx context.Context, r Run) (created bool, err error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return false, err
	}
	defer tx.Rollback()

	now := formatTime(time.Now())
	res, err := tx.ExecContext(ctx, `
		INSERT INTO run (id, outcome, started_at, ended_at, received_at)
		VALUES ($1, $2, $3, $4, $5)
		ON CONFLICT (id) DO NOTHING`,
		r.ID, r.Outcome, formatTime(r.StartedAt), formatTime(r.EndedAt), now)
	if err != nil {
		return false, err
	}
	if n, err := res.RowsAffected(); err != nil || n == 0 {
		return false, err
	}

	for _, e := range r.Earners {
		playerID, err := playerFor(ctx, tx, e.FirebaseUID, now)
		if err != nil {
			return false, err
		}
		// Sorted, so rows are written in the same order every time.
		for _, itemID := range slices.Sorted(maps.Keys(e.Items)) {
			if err := addItem(ctx, tx, playerID, itemID, e.Items[itemID], r.ID, now); err != nil {
				return false, err
			}
		}
	}
	return true, tx.Commit()
}

// playerFor returns the player logged in as uid, making the player and its
// login first if there is none.
func playerFor(ctx context.Context, tx *sql.Tx, uid, now string) (string, error) {
	var id string
	err := tx.QueryRowContext(ctx, `
		SELECT player_id FROM player_login WHERE provider = $1 AND subject = $2`,
		firebase, uid).Scan(&id)
	if !errors.Is(err, sql.ErrNoRows) {
		return id, err
	}
	// Version 7 UUIDs sort by creation time, which keeps the index compact.
	newID, err := uuid.NewV7()
	if err != nil {
		return "", err
	}
	id = newID.String()
	if _, err := tx.ExecContext(ctx, `INSERT INTO player (id, created_at) VALUES ($1, $2)`, id, now); err != nil {
		return "", err
	}
	_, err = tx.ExecContext(ctx, `
		INSERT INTO player_login (provider, subject, player_id, created_at)
		VALUES ($1, $2, $3, $4)`, firebase, uid, id, now)
	return id, err
}

// addItem writes a run's ledger row for one item and adds it to the
// player's inventory.
func addItem(ctx context.Context, tx *sql.Tx, playerID, itemID string, amount int64, runID, now string) error {
	var disabledAt sql.NullString
	err := tx.QueryRowContext(ctx, `SELECT disabled_at FROM item WHERE id = $1`, itemID).Scan(&disabledAt)
	switch {
	case errors.Is(err, sql.ErrNoRows):
		return fmt.Errorf("%w: %q", ErrUnknownItem, itemID)
	case err != nil:
		return err
	case disabledAt.Valid:
		return fmt.Errorf("%w: %q", ErrDisabledItem, itemID)
	}
	_, err = tx.ExecContext(ctx, `
		INSERT INTO ledger (player_id, item_id, amount, reason, run_id, created_at)
		VALUES ($1, $2, $3, 'run', $4, $5)`, playerID, itemID, amount, runID, now)
	if err != nil {
		return err
	}
	_, err = tx.ExecContext(ctx, `
		INSERT INTO inventory (player_id, item_id, count) VALUES ($1, $2, $3)
		ON CONFLICT (player_id, item_id) DO UPDATE SET count = inventory.count + excluded.count`,
		playerID, itemID, amount)
	return err
}
