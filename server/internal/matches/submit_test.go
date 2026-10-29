package matches_test

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"

	"game/server/internal/auth"
	"game/server/internal/matches"
	"game/server/internal/testdb"
)

func insertPlayer(t *testing.T, pool *pgxpool.Pool) (id uuid.UUID, token string) {
	t.Helper()
	token, tokenHash := auth.NewToken()
	err := pool.QueryRow(context.Background(), `
		INSERT INTO player (token_hash) VALUES ($1) RETURNING id`, tokenHash).Scan(&id)
	if err != nil {
		t.Fatalf("insert player: %v", err)
	}
	return id, token
}

func handler(pool *pgxpool.Pool) http.Handler {
	mux := http.NewServeMux()
	matches.New(pool).Register(mux)
	return mux
}

func submission(t *testing.T, matchID, playerID uuid.UUID) []byte {
	t.Helper()
	ended := time.Now().UTC().Truncate(time.Second)
	body, err := json.Marshal(map[string]any{
		"match_id":        matchID,
		"balance_version": "v1",
		"outcome":         "win",
		"started_at":      ended.Add(-10 * time.Minute),
		"ended_at":        ended,
		"participants": []map[string]any{{
			"player_id":    playerID,
			"character_id": "knight",
			"stats":        map[string]int{"damage_dealt": 1200, "kills": 7},
			"items":        []string{"iron_sword", "health_potion"},
		}},
	})
	if err != nil {
		t.Fatalf("marshal submission: %v", err)
	}
	return body
}

func post(h http.Handler, token string, body []byte) int {
	req := httptest.NewRequest(http.MethodPost, "/matches", bytes.NewReader(body))
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec.Code
}

func assertRewardedOnce(t *testing.T, pool *pgxpool.Pool, matchID, playerID uuid.UUID) {
	t.Helper()
	ctx := context.Background()

	var rows int
	var reward int64
	err := pool.QueryRow(ctx, `
		SELECT count(*), coalesce(sum(reward), 0)
		FROM match_participant WHERE match_id = $1 AND player_id = $2`,
		matchID, playerID).Scan(&rows, &reward)
	if err != nil {
		t.Fatalf("read participant: %v", err)
	}
	if rows != 1 {
		t.Fatalf("participant rows = %d, want 1", rows)
	}
	if reward <= 0 {
		t.Fatalf("reward = %d, want > 0 for a win", reward)
	}

	var currency int64
	if err := pool.QueryRow(ctx, `SELECT currency FROM player WHERE id = $1`, playerID).Scan(&currency); err != nil {
		t.Fatalf("read currency: %v", err)
	}
	if currency != reward {
		t.Fatalf("currency = %d, want %d (the reward, granted once)", currency, reward)
	}
}

func TestSubmitIsIdempotent(t *testing.T) {
	pool := testdb.New(t)
	h := handler(pool)

	t.Run("sequential replay", func(t *testing.T) {
		matchID := uuid.New()
		playerID, token := insertPlayer(t, pool)
		body := submission(t, matchID, playerID)

		if code := post(h, token, body); code != http.StatusCreated {
			t.Fatalf("first POST = %d, want 201", code)
		}
		if code := post(h, token, body); code != http.StatusOK {
			t.Fatalf("replayed POST = %d, want 200", code)
		}
		assertRewardedOnce(t, pool, matchID, playerID)
	})

	t.Run("concurrent replay", func(t *testing.T) {
		matchID := uuid.New()
		playerID, token := insertPlayer(t, pool)
		body := submission(t, matchID, playerID)

		const n = 10
		codes := make([]int, n)
		var wg sync.WaitGroup
		for i := range n {
			wg.Go(func() { codes[i] = post(h, token, body) })
		}
		wg.Wait()

		created := 0
		for _, code := range codes {
			switch code {
			case http.StatusCreated:
				created++
			case http.StatusOK:
			default:
				t.Fatalf("POST = %d, want 201 or 200; all codes: %v", code, codes)
			}
		}
		if created != 1 {
			t.Fatalf("got %d 201 responses, want exactly 1; all codes: %v", created, codes)
		}
		assertRewardedOnce(t, pool, matchID, playerID)
	})
}

func TestSubmitRejectsBadRequests(t *testing.T) {
	pool := testdb.New(t)
	h := handler(pool)
	playerID, token := insertPlayer(t, pool)
	otherID, _ := insertPlayer(t, pool)

	withOutcome := func(outcome string) []byte {
		var m map[string]any
		if err := json.Unmarshal(submission(t, uuid.New(), playerID), &m); err != nil {
			t.Fatalf("unmarshal submission: %v", err)
		}
		m["outcome"] = outcome
		body, err := json.Marshal(m)
		if err != nil {
			t.Fatalf("marshal submission: %v", err)
		}
		return body
	}

	tests := []struct {
		name  string
		token string
		body  []byte
		want  int
	}{
		{"no token", "", submission(t, uuid.New(), playerID), http.StatusUnauthorized},
		{"unknown token", "nope", submission(t, uuid.New(), playerID), http.StatusUnauthorized},
		{"malformed JSON", token, []byte(`{"match_id":`), http.StatusBadRequest},
		{"invalid outcome", token, withOutcome("draw"), http.StatusBadRequest},
		{"submitter not a participant", token, submission(t, uuid.New(), otherID), http.StatusForbidden},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if code := post(h, tt.token, tt.body); code != tt.want {
				t.Fatalf("POST = %d, want %d", code, tt.want)
			}
		})
	}

	var currency int64
	if err := pool.QueryRow(context.Background(), `SELECT currency FROM player WHERE id = $1`, playerID).Scan(&currency); err != nil {
		t.Fatalf("read currency: %v", err)
	}
	if currency != 0 {
		t.Fatalf("currency = %d after rejected submissions, want 0", currency)
	}
}
