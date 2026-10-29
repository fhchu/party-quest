package players_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"game/server/internal/players"
	"game/server/internal/testdb"
)

func do(t *testing.T, h http.Handler, method, path, token, body string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

func TestAccountAndProfile(t *testing.T) {
	mux := http.NewServeMux()
	players.New(testdb.New(t)).Register(mux)

	rec := do(t, mux, http.MethodPost, "/players", "", "")
	if rec.Code != http.StatusCreated {
		t.Fatalf("POST /players = %d, want 201", rec.Code)
	}
	var account struct {
		PlayerID string `json:"player_id"`
		Token    string `json:"token"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &account); err != nil || account.PlayerID == "" || account.Token == "" {
		t.Fatalf("POST /players body = %s (%v), want player_id and token", rec.Body, err)
	}

	if rec := do(t, mux, http.MethodGet, "/profile", "", ""); rec.Code != http.StatusUnauthorized {
		t.Fatalf("GET /profile without token = %d, want 401", rec.Code)
	}
	if rec := do(t, mux, http.MethodPut, "/profile/data", account.Token, `[1, 2]`); rec.Code != http.StatusBadRequest {
		t.Fatalf("PUT /profile/data with an array = %d, want 400", rec.Code)
	}
	if rec := do(t, mux, http.MethodPut, "/profile/data", account.Token, `{"level": 3}`); rec.Code != http.StatusNoContent {
		t.Fatalf("PUT /profile/data = %d, want 204", rec.Code)
	}

	rec = do(t, mux, http.MethodGet, "/profile", account.Token, "")
	if rec.Code != http.StatusOK {
		t.Fatalf("GET /profile = %d, want 200", rec.Code)
	}
	var profile struct {
		PlayerID string         `json:"player_id"`
		Currency int64          `json:"currency"`
		Data     map[string]int `json:"data"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &profile); err != nil {
		t.Fatalf("decode profile: %v", err)
	}
	if profile.PlayerID != account.PlayerID || profile.Currency != 0 || profile.Data["level"] != 3 {
		t.Fatalf("profile = %+v, want id %s, currency 0, data level 3", profile, account.PlayerID)
	}
}
