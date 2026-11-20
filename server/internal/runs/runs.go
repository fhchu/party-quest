// Package runs records finished runs reported by the game server.
//
// A submission carries a run ID the game server made. Submitting the same run
// again changes nothing and reports success, so the game server can retry
// after a timeout without paying anyone twice.
package runs

import (
	"errors"
	"fmt"
	"net/http"
	"slices"
	"time"

	"github.com/google/uuid"

	"game/server/internal/auth"
	"game/server/internal/httpjson"
	"game/server/internal/store"
)

// maxEarners is the party size. Must match MAX_PLAYERS in
// game/server/lobby.gd.
const maxEarners = 4

// outcomes are the values of run.outcome. They must match the CHECK in
// migrations/00001_init.sql.
var outcomes = []string{"won", "lost", "abandoned"}

// API serves run submission.
type API struct {
	store *store.Store
	token string
}

// New returns an API that records runs in s and accepts only callers that
// send token.
func New(s *store.Store, token string) *API {
	return &API{store: s, token: token}
}

// Register adds POST /runs, which requires the game server's token.
func (a *API) Register(mux *http.ServeMux) {
	mux.Handle("POST /runs", auth.RequireToken(a.token, http.HandlerFunc(a.submit)))
}

// submission is the body of POST /runs.
type submission struct {
	RunID     string    `json:"run_id"`
	Outcome   string    `json:"outcome"`
	StartedAt time.Time `json:"started_at"`
	EndedAt   time.Time `json:"ended_at"`
	Earners   []earner  `json:"earners"`
}

// earner is one player's net item changes, keyed by item ID.
type earner struct {
	FirebaseUID string           `json:"firebase_uid"`
	Items       map[string]int64 `json:"items"`
}

// validate checks what the schema can't, or can't report clearly.
func (s *submission) validate() error {
	if _, err := uuid.Parse(s.RunID); err != nil {
		return fmt.Errorf("run_id must be a UUID: %w", err)
	}
	if !slices.Contains(outcomes, s.Outcome) {
		return fmt.Errorf("outcome must be one of %q", outcomes)
	}
	switch {
	case s.StartedAt.IsZero() || s.EndedAt.IsZero():
		return errors.New("started_at and ended_at are required")
	case s.EndedAt.Before(s.StartedAt):
		return errors.New("ended_at is before started_at")
	case len(s.Earners) > maxEarners:
		return fmt.Errorf("a run has at most %d earners", maxEarners)
	}
	seen := map[string]bool{}
	for _, e := range s.Earners {
		if e.FirebaseUID == "" || seen[e.FirebaseUID] {
			return errors.New("each earner needs its own firebase_uid")
		}
		seen[e.FirebaseUID] = true
		if len(e.Items) == 0 {
			return errors.New("each earner needs at least one item")
		}
		for id, amount := range e.Items {
			if id == "" || amount == 0 {
				return errors.New("items need an ID and an amount other than 0")
			}
		}
	}
	return nil
}

func (s *submission) run() store.Run {
	r := store.Run{ID: s.RunID, Outcome: s.Outcome, StartedAt: s.StartedAt, EndedAt: s.EndedAt}
	for _, e := range s.Earners {
		r.Earners = append(r.Earners, store.Earner{FirebaseUID: e.FirebaseUID, Items: e.Items})
	}
	return r
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
	created, err := a.store.RecordRun(r.Context(), s.run())
	if errors.Is(err, store.ErrUnknownItem) || errors.Is(err, store.ErrDisabledItem) {
		httpjson.Error(w, http.StatusUnprocessableEntity, err.Error())
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
	httpjson.Write(w, status, map[string]string{"run_id": s.RunID})
}
