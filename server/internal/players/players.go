// Package players creates anonymous accounts and serves the caller's profile.
package players

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"

	"game/server/internal/auth"
	"game/server/internal/httpjson"
)

type API struct {
	pool *pgxpool.Pool
}

func New(pool *pgxpool.Pool) *API {
	return &API{pool: pool}
}

// Register adds:
//
//	POST /players       create an account; returns its ID and bearer token
//	GET  /profile       the caller's currency and saved data
//	PUT  /profile/data  replace the caller's saved data (a JSON object)
func (a *API) Register(mux *http.ServeMux) {
	mux.HandleFunc("POST /players", a.create)
	mux.Handle("GET /profile", auth.Require(a.pool, http.HandlerFunc(a.profile)))
	mux.Handle("PUT /profile/data", auth.Require(a.pool, http.HandlerFunc(a.putData)))
}

func (a *API) create(w http.ResponseWriter, r *http.Request) {
	token, hash := auth.NewToken()
	var id uuid.UUID
	err := a.pool.QueryRow(r.Context(), `
		INSERT INTO player (token_hash) VALUES ($1) RETURNING id`, hash).Scan(&id)
	if err != nil {
		httpjson.InternalError(w, r, err)
		return
	}
	httpjson.Write(w, http.StatusCreated, map[string]any{"player_id": id, "token": token})
}

func (a *API) profile(w http.ResponseWriter, r *http.Request) {
	id, _ := auth.PlayerID(r.Context())
	var p struct {
		PlayerID  uuid.UUID       `json:"player_id"`
		Currency  int64           `json:"currency"`
		Data      json.RawMessage `json:"data"`
		CreatedAt time.Time       `json:"created_at"`
	}
	err := a.pool.QueryRow(r.Context(), `
		SELECT id, currency, data, created_at FROM player WHERE id = $1`, id).
		Scan(&p.PlayerID, &p.Currency, &p.Data, &p.CreatedAt)
	if err != nil {
		httpjson.InternalError(w, r, err)
		return
	}
	httpjson.Write(w, http.StatusOK, p)
}

func (a *API) putData(w http.ResponseWriter, r *http.Request) {
	id, _ := auth.PlayerID(r.Context())
	var data map[string]json.RawMessage
	if err := httpjson.Decode(w, r, &data); err != nil || data == nil {
		httpjson.Error(w, http.StatusBadRequest, "body must be a JSON object")
		return
	}
	if _, err := a.pool.Exec(r.Context(), `UPDATE player SET data = $2 WHERE id = $1`, id, data); err != nil {
		httpjson.InternalError(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
