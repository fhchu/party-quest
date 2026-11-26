package runs_test

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"game/server/internal/httpapi"
	"game/server/internal/runs"
	"game/server/internal/store"
	"game/server/internal/testdb"
	"game/server/items"
)

const (
	token  = "test-game-server-token"
	runID  = "0192f6a8-0000-7000-8000-000000000001"
	runID2 = "0192f6a8-0000-7000-8000-000000000002"
	alice  = "firebase-alice"
	bob    = "firebase-bob"
)

var (
	start   = time.Date(2026, 11, 17, 21, 0, 0, 0, time.UTC)
	end     = start.Add(8 * time.Minute)
	retired = start.Add(-time.Hour)
)

type env struct {
	db      *sql.DB
	handler http.Handler
}

func newEnv(t *testing.T) env {
	t.Helper()
	sqlDB := testdb.New(t)
	st := store.New(sqlDB)
	err := st.SyncItems(context.Background(), []items.Item{
		{ID: "gold", Name: "Gold"},
		{ID: "potion", Name: "Potion"},
		{ID: "old-sword", Name: "Old sword", DisabledAt: &retired},
	})
	if err != nil {
		t.Fatalf("sync items: %v", err)
	}
	return env{db: sqlDB, handler: httpapi.New(sqlDB, runs.New(st, token)).Handler()}
}

func body(id, outcome string, earners map[string]map[string]int64) map[string]any {
	list := []map[string]any{}
	for uid, its := range earners {
		list = append(list, map[string]any{"firebase_uid": uid, "items": its})
	}
	return map[string]any{
		"run_id": id, "outcome": outcome, "started_at": start, "ended_at": end, "earners": list,
	}
}

func (e env) post(t *testing.T, auth string, v any) *httptest.ResponseRecorder {
	t.Helper()
	b, err := json.Marshal(v)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	req := httptest.NewRequest(http.MethodPost, "/runs", bytes.NewReader(b))
	if auth != "" {
		req.Header.Set("Authorization", auth)
	}
	rec := httptest.NewRecorder()
	e.handler.ServeHTTP(rec, req)
	return rec
}

func (e env) submit(t *testing.T, v any) int {
	t.Helper()
	return e.post(t, "Bearer "+token, v).Code
}

func (e env) count(t *testing.T, uid, item string) int64 {
	t.Helper()
	var n int64
	err := e.db.QueryRowContext(context.Background(), `
		SELECT COALESCE(SUM(i.count), 0) FROM inventory i
		JOIN player_login l ON l.player_id = i.player_id
		WHERE l.subject = $1 AND i.item_id = $2`, uid, item).Scan(&n)
	if err != nil {
		t.Fatalf("count: %v", err)
	}
	return n
}

func (e env) rows(t *testing.T, query string) int {
	t.Helper()
	var n int
	if err := e.db.QueryRowContext(context.Background(), query).Scan(&n); err != nil {
		t.Fatalf("%s: %v", query, err)
	}
	return n
}

func TestMissingOrWrongTokenIsRefused(t *testing.T) {
	e := newEnv(t)
	win := body(runID, "won", map[string]map[string]int64{alice: {"gold": 1}})
	for _, auth := range []string{"", "Bearer wrong", token} {
		if code := e.post(t, auth, win).Code; code != http.StatusUnauthorized {
			t.Errorf("Authorization %q: %d, want 401", auth, code)
		}
	}
	if n := e.rows(t, `SELECT COUNT(*) FROM run`); n != 0 {
		t.Fatalf("runs stored = %d, want 0", n)
	}
}

func TestBadBodiesAreRefused(t *testing.T) {
	e := newEnv(t)
	gold := map[string]int64{"gold": 1}
	tooMany := map[string]map[string]int64{"a": gold, "b": gold, "c": gold, "d": gold, "e": gold}
	backwards := body(runID, "won", nil)
	backwards["ended_at"] = start.Add(-time.Minute)
	unknownField := body(runID, "won", nil)
	unknownField["score"] = 3
	duplicate := body(runID, "won", nil)
	duplicate["earners"] = []map[string]any{
		{"firebase_uid": alice, "items": gold}, {"firebase_uid": alice, "items": gold},
	}
	tests := map[string]any{
		"run_id not a UUID":      body("run-1", "won", nil),
		"unknown outcome":        body(runID, "draw", nil),
		"ends before it starts":  backwards,
		"too many earners":       body(runID, "won", tooMany),
		"earner without an item": body(runID, "won", map[string]map[string]int64{alice: {}}),
		"amount of 0":            body(runID, "won", map[string]map[string]int64{alice: {"gold": 0}}),
		"earner listed twice":    duplicate,
		"field the API lacks":    unknownField,
		"earner without a UID":   body(runID, "won", map[string]map[string]int64{"": gold}),
	}
	for name, v := range tests {
		if code := e.submit(t, v); code != http.StatusBadRequest {
			t.Errorf("%s: %d, want 400", name, code)
		}
	}
}

func TestWinPaysEachEarnerOnce(t *testing.T) {
	e := newEnv(t)
	win := body(runID, "won", map[string]map[string]int64{alice: {"gold": 1}, bob: {"gold": 1, "potion": 2}})
	if code := e.submit(t, win); code != http.StatusCreated {
		t.Fatalf("first submit: %d, want 201", code)
	}
	if code := e.submit(t, win); code != http.StatusOK {
		t.Fatalf("retry: %d, want 200", code)
	}
	for _, c := range []struct {
		uid, item string
		want      int64
	}{{alice, "gold", 1}, {bob, "gold", 1}, {bob, "potion", 2}, {alice, "potion", 0}} {
		if got := e.count(t, c.uid, c.item); got != c.want {
			t.Errorf("%s's %s = %d, want %d", c.uid, c.item, got, c.want)
		}
	}
	if n := e.rows(t, `SELECT COUNT(*) FROM ledger`); n != 3 {
		t.Fatalf("ledger rows = %d, want 3", n)
	}
}

func TestSecondWinAddsToTheSamePlayer(t *testing.T) {
	e := newEnv(t)
	for _, id := range []string{runID, runID2} {
		if code := e.submit(t, body(id, "won", map[string]map[string]int64{alice: {"gold": 1}})); code != http.StatusCreated {
			t.Fatalf("submit %s: %d, want 201", id, code)
		}
	}
	if got := e.count(t, alice, "gold"); got != 2 {
		t.Fatalf("alice's gold = %d, want 2", got)
	}
	if n := e.rows(t, `SELECT COUNT(*) FROM player`); n != 1 {
		t.Fatalf("players = %d, want 1", n)
	}
}

func TestLedgerSumsEqualInventoryCounts(t *testing.T) {
	e := newEnv(t)
	e.submit(t, body(runID, "won", map[string]map[string]int64{alice: {"gold": 1, "potion": 3}}))
	e.submit(t, body(runID2, "won", map[string]map[string]int64{alice: {"gold": 1, "potion": -1}}))
	mismatches := e.rows(t, `
		SELECT COUNT(*) FROM inventory i
		WHERE i.count <> (SELECT SUM(amount) FROM ledger l
			WHERE l.player_id = i.player_id AND l.item_id = i.item_id)`)
	if mismatches != 0 {
		t.Fatalf("%d inventory counts differ from their ledger sums", mismatches)
	}
	if got := e.count(t, alice, "potion"); got != 2 {
		t.Fatalf("alice's potions = %d, want 2", got)
	}
}

func TestUnknownOrDisabledItemStoresNothing(t *testing.T) {
	e := newEnv(t)
	for _, item := range []string{"pebble", "old-sword"} {
		v := body(runID, "won", map[string]map[string]int64{alice: {"gold": 1, item: 1}})
		if code := e.submit(t, v); code != http.StatusUnprocessableEntity {
			t.Errorf("%s: %d, want 422", item, code)
		}
	}
	for _, table := range []string{"run", "player", "ledger", "inventory"} {
		if n := e.rows(t, `SELECT COUNT(*) FROM `+table); n != 0 {
			t.Errorf("%s rows = %d, want 0", table, n)
		}
	}
}

func TestRunWithNoEarnersIsStored(t *testing.T) {
	e := newEnv(t)
	for id, outcome := range map[string]string{runID: "lost", runID2: "abandoned"} {
		if code := e.submit(t, body(id, outcome, nil)); code != http.StatusCreated {
			t.Errorf("%s: %d, want 201", outcome, code)
		}
	}
	if n := e.rows(t, `SELECT COUNT(*) FROM run`); n != 2 {
		t.Fatalf("runs = %d, want 2", n)
	}
	if n := e.rows(t, `SELECT COUNT(*) FROM ledger`); n != 0 {
		t.Fatalf("ledger rows = %d, want 0", n)
	}
}
