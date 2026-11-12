package matches

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"slices"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgerrcode"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"game/server/internal/auth"
	"game/server/internal/httpjson"
)

// Values of match.outcome and match.status. They must match the CHECK
// constraints in migrations/00001_init.sql.
const (
	OutcomeWin      = "win"
	OutcomeLoss     = "loss"
	StatusCompleted = "completed"
)

// PLACEHOLDER (design): currency paid to every participant. Currency itself
// is a roguelite assumption the roadmap expects to revisit.
const (
	winReward  = 100
	lossReward = 25
)

// maxParticipants is the party size. Must match MAX_PLAYERS in
// game/server/lobby.gd.
const maxParticipants = 4

// API serves match submission.
type API struct {
	pool *pgxpool.Pool
}

// New returns an API backed by pool.
func New(pool *pgxpool.Pool) *API {
	return &API{pool: pool}
}

// Register adds POST /matches, which requires a bearer token belonging to
// one of the match's participants.
func (a *API) Register(mux *http.ServeMux) {
	mux.Handle("POST /matches", auth.Require(a.pool, http.HandlerFunc(a.submit)))
}

// submission is the body of POST /matches.
type submission struct {
	MatchID        uuid.UUID     `json:"match_id"`
	BalanceVersion string        `json:"balance_version"`
	Outcome        string        `json:"outcome"`
	StartedAt      time.Time     `json:"started_at"`
	EndedAt        time.Time     `json:"ended_at"`
	Participants   []participant `json:"participants"`
}

// participant is one player's part of a submission.
type participant struct {
	PlayerID    uuid.UUID                  `json:"player_id"`
	CharacterID string                     `json:"character_id"`
	Stats       map[string]json.RawMessage `json:"stats"`
	Items       []string                   `json:"items"`
}

// validate checks what the schema can't, or can't report clearly.
func (s *submission) validate() error {
	switch {
	case s.MatchID == uuid.Nil:
		return errors.New("match_id is required")
	case s.BalanceVersion == "":
		return errors.New("balance_version is required")
	case s.Outcome != OutcomeWin && s.Outcome != OutcomeLoss:
		return fmt.Errorf("outcome must be %q or %q", OutcomeWin, OutcomeLoss)
	case s.StartedAt.IsZero() || s.EndedAt.IsZero():
		return errors.New("started_at and ended_at are required")
	case s.EndedAt.Before(s.StartedAt):
		return errors.New("ended_at is before started_at")
	case len(s.Participants) == 0 || len(s.Participants) > maxParticipants:
		return fmt.Errorf("a match needs 1 to %d participants", maxParticipants)
	}
	seen := map[uuid.UUID]bool{}
	for _, p := range s.Participants {
		if seen[p.PlayerID] {
			return errors.New("duplicate player_id in participants")
		}
		seen[p.PlayerID] = true
		if p.CharacterID == "" {
			return errors.New("character_id is required")
		}
		items := map[string]bool{}
		for _, item := range p.Items {
			if item == "" || items[item] {
				return errors.New("items must be unique and non-empty")
			}
			items[item] = true
		}
	}
	return nil
}

func (a *API) submit(w http.ResponseWriter, r *http.Request) {
	var s submission
	if err := httpjson.Decode(w, r, &s); err != nil {
		httpjson.Error(w, http.StatusBadRequest, err.Error())
		return
	}
	if err := s.validate(); err != nil {
		httpjson.Error(w, http.StatusBadRequest, err.Error())
		return
	}
	submitter, _ := auth.PlayerID(r.Context())
	if !slices.ContainsFunc(s.Participants, func(p participant) bool { return p.PlayerID == submitter }) {
		httpjson.Error(w, http.StatusForbidden, "only a participant can submit a match")
		return
	}

	created, err := a.record(r.Context(), s)
	var pgErr *pgconn.PgError
	// The only foreign keys a submission can break point at player.
	if errors.As(err, &pgErr) && pgErr.Code == pgerrcode.ForeignKeyViolation {
		httpjson.Error(w, http.StatusUnprocessableEntity, "unknown player_id in participants")
		return
	}
	if err != nil {
		httpjson.InternalError(w, r, err)
		return
	}

	status := http.StatusOK
	if created {
		status = http.StatusCreated
	}
	httpjson.Write(w, status, map[string]any{"match_id": s.MatchID})
}

// record stores the match and pays its rewards in one transaction, or does
// nothing and reports created=false if the match ID is already stored.
// Concurrent submissions of the same ID block on the primary key until the
// first commits, so the reward cannot be paid twice.
func (a *API) record(ctx context.Context, s submission) (created bool, err error) {
	reward := lossReward
	if s.Outcome == OutcomeWin {
		reward = winReward
	}
	// Lock player rows in a fixed order so matches sharing players can't deadlock.
	slices.SortFunc(s.Participants, func(x, y participant) int {
		return bytes.Compare(x.PlayerID[:], y.PlayerID[:])
	})

	err = pgx.BeginFunc(ctx, a.pool, func(tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, `
			INSERT INTO match (id, balance_version, status, outcome, started_at, ended_at)
			VALUES ($1, $2, $3, $4, $5, $6)
			ON CONFLICT (id) DO NOTHING`,
			s.MatchID, s.BalanceVersion, StatusCompleted, s.Outcome, s.StartedAt, s.EndedAt)
		if err != nil || tag.RowsAffected() == 0 {
			return err
		}
		created = true

		// One round trip for every row, instead of one per row. Queued
		// statements run in order, so the player rows still lock in ID order.
		var b pgx.Batch
		for _, p := range s.Participants {
			stats := p.Stats
			if stats == nil {
				stats = map[string]json.RawMessage{}
			}
			b.Queue(`
				INSERT INTO match_participant (match_id, player_id, character_id, stats, reward)
				VALUES ($1, $2, $3, $4, $5)`,
				s.MatchID, p.PlayerID, p.CharacterID, stats, reward)
			b.Queue(`UPDATE player SET currency = currency + $2 WHERE id = $1`, p.PlayerID, reward)
			for _, item := range p.Items {
				b.Queue(`
					INSERT INTO match_participant_item (match_id, player_id, item_id)
					VALUES ($1, $2, $3)`,
					s.MatchID, p.PlayerID, item)
			}
		}
		// Close reads every result and returns the first error.
		return tx.SendBatch(ctx, &b).Close()
	})
	return created, err
}
