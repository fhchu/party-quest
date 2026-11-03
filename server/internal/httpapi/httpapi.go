// Package httpapi assembles the HTTP API: health checks plus the routes
// registered by the feature packages.
package httpapi

import (
	"context"
	"net/http"
	"time"

	"game/server/internal/httpjson"
)

// readyTimeout bounds the database ping behind GET /ready, so a hung
// database reports unavailable instead of hanging the health checker.
// Untuned.
const readyTimeout = 2 * time.Second

// Pinger checks that the database answers. *pgxpool.Pool implements it.
type Pinger interface {
	Ping(ctx context.Context) error
}

// Registrar is implemented by feature packages that add routes to the API.
type Registrar interface {
	Register(mux *http.ServeMux)
}

// API is the whole HTTP API.
type API struct {
	db     Pinger
	routes []Registrar
}

// New returns an API that checks db for readiness and serves routes.
func New(db Pinger, routes ...Registrar) *API {
	return &API{db: db, routes: routes}
}

// Handler serves GET /health, which never touches the database, and
// GET /ready, which does, along with every registered route.
func (a *API) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", a.health)
	mux.HandleFunc("GET /ready", a.ready)
	for _, r := range a.routes {
		r.Register(mux)
	}
	return mux
}

func (a *API) health(w http.ResponseWriter, _ *http.Request) {
	httpjson.Write(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (a *API) ready(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), readyTimeout)
	defer cancel()
	if err := a.db.Ping(ctx); err != nil {
		httpjson.Write(w, http.StatusServiceUnavailable, map[string]string{"status": "database unavailable"})
		return
	}
	httpjson.Write(w, http.StatusOK, map[string]string{"status": "ready"})
}
