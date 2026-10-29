package stats_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"

	"game/server/internal/auth"
	"game/server/internal/stats"
	"game/server/internal/testdb"
)

type row struct {
	ID       string  `json:"id"`
	Picks    int64   `json:"picks"`
	Wins     int64   `json:"wins"`
	PickRate float64 `json:"pick_rate"`
	WinRate  float64 `json:"win_rate"`
}

func seedMatch(t *testing.T, pool *pgxpool.Pool, version, outcome, character string, items ...string) {
	t.Helper()
	ctx := context.Background()
	_, hash := auth.NewToken()
	matchID := uuid.New()

	var playerID uuid.UUID
	err := pool.QueryRow(ctx, `INSERT INTO player (token_hash) VALUES ($1) RETURNING id`, hash).Scan(&playerID)
	if err == nil {
		_, err = pool.Exec(ctx, `
			INSERT INTO match (id, balance_version, status, outcome, ended_at)
			VALUES ($1, $2, 'completed', $3, now())`, matchID, version, outcome)
	}
	if err == nil {
		_, err = pool.Exec(ctx, `
			INSERT INTO match_participant (match_id, player_id, character_id)
			VALUES ($1, $2, $3)`, matchID, playerID, character)
	}
	for _, item := range items {
		if err == nil {
			_, err = pool.Exec(ctx, `
				INSERT INTO match_participant_item (match_id, player_id, item_id)
				VALUES ($1, $2, $3)`, matchID, playerID, item)
		}
	}
	if err != nil {
		t.Fatalf("seed match: %v", err)
	}
}

func get(t *testing.T, h http.Handler, path, key string) []row {
	t.Helper()
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, path, nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("GET %s = %d, want 200", path, rec.Code)
	}
	var body map[string]json.RawMessage
	var rows []row
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode %s: %v", path, err)
	}
	if err := json.Unmarshal(body[key], &rows); err != nil {
		t.Fatalf("decode %s %q: %v", path, key, err)
	}
	return rows
}

func assertRows(t *testing.T, got, want []row) {
	t.Helper()
	if got == nil && want != nil {
		t.Fatalf("rows = null, want %+v", want)
	}
	if len(got) != len(want) {
		t.Fatalf("rows = %+v, want %+v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("row %d = %+v, want %+v", i, got[i], want[i])
		}
	}
}

func TestStats(t *testing.T) {
	pool := testdb.New(t)
	mux := http.NewServeMux()
	stats.New(pool).Register(mux)

	seedMatch(t, pool, "v1", "win", "knight", "sword")
	seedMatch(t, pool, "v1", "loss", "knight", "sword", "shield")
	seedMatch(t, pool, "v1", "win", "mage")
	seedMatch(t, pool, "v1", "win", "mage", "staff")
	seedMatch(t, pool, "v2", "loss", "knight", "sword")

	assertRows(t, get(t, mux, "/stats/characters?balance_version=v1", "characters"), []row{
		{ID: "knight", Picks: 2, Wins: 1, PickRate: 0.5, WinRate: 0.5},
		{ID: "mage", Picks: 2, Wins: 2, PickRate: 0.5, WinRate: 1},
	})
	assertRows(t, get(t, mux, "/stats/items?balance_version=v1", "items"), []row{
		{ID: "sword", Picks: 2, Wins: 1, PickRate: 0.5, WinRate: 0.5},
		{ID: "shield", Picks: 1, Wins: 0, PickRate: 0.25, WinRate: 0},
		{ID: "staff", Picks: 1, Wins: 1, PickRate: 0.25, WinRate: 1},
	})
	assertRows(t, get(t, mux, "/stats/items?balance_version=v3", "items"), []row{})

	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/stats/items", nil))
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("GET /stats/items without balance_version = %d, want 400", rec.Code)
	}
}
