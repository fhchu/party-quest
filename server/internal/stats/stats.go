// Package stats serves balance statistics computed from completed matches.
package stats

import (
	"context"
	"net/http"

	"github.com/jackc/pgx/v5/pgxpool"

	"game/server/internal/httpjson"
)

type API struct {
	pool *pgxpool.Pool
}

func New(pool *pgxpool.Pool) *API {
	return &API{pool: pool}
}

// Register adds GET /stats/characters and GET /stats/items. Both require a
// balance_version query parameter, since numbers from different balance
// versions aren't comparable.
func (a *API) Register(mux *http.ServeMux) {
	mux.HandleFunc("GET /stats/characters", a.serve("characters", charactersQuery))
	mux.HandleFunc("GET /stats/items", a.serve("items", itemsQuery))
}

// Each query takes the balance version as $1 and returns (id, picks, wins,
// total), where total is the denominator for the pick rate.
const (
	charactersQuery = `
		SELECT mp.character_id,
		       count(*),
		       count(*) FILTER (WHERE m.outcome = 'win'),
		       (sum(count(*)) OVER ())::bigint
		FROM match_participant mp
		JOIN match m ON m.id = mp.match_id
		WHERE m.balance_version = $1 AND m.status = 'completed'
		GROUP BY mp.character_id
		ORDER BY 2 DESC, 1`

	// An item's pick rate is the share of participants who carried it.
	itemsQuery = `
		WITH p AS (
			SELECT mp.match_id, mp.player_id, m.outcome
			FROM match_participant mp
			JOIN match m ON m.id = mp.match_id
			WHERE m.balance_version = $1 AND m.status = 'completed'
		)
		SELECT i.item_id,
		       count(*),
		       count(*) FILTER (WHERE p.outcome = 'win'),
		       (SELECT count(*) FROM p)
		FROM match_participant_item i
		JOIN p USING (match_id, player_id)
		GROUP BY i.item_id
		ORDER BY 2 DESC, 1`
)

type row struct {
	ID       string  `json:"id"`
	Picks    int64   `json:"picks"`
	Wins     int64   `json:"wins"`
	PickRate float64 `json:"pick_rate"`
	WinRate  float64 `json:"win_rate"`
}

func (a *API) serve(key, query string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		version := r.URL.Query().Get("balance_version")
		if version == "" {
			httpjson.Error(w, http.StatusBadRequest, "balance_version is required")
			return
		}
		rows, err := a.query(r.Context(), query, version)
		if err != nil {
			httpjson.InternalError(w, r, err)
			return
		}
		httpjson.Write(w, http.StatusOK, map[string]any{"balance_version": version, key: rows})
	}
}

func (a *API) query(ctx context.Context, query, version string) ([]row, error) {
	rs, err := a.pool.Query(ctx, query, version)
	if err != nil {
		return nil, err
	}
	defer rs.Close()

	out := []row{}
	for rs.Next() {
		var r row
		var total int64
		if err := rs.Scan(&r.ID, &r.Picks, &r.Wins, &total); err != nil {
			return nil, err
		}
		r.PickRate = float64(r.Picks) / float64(total)
		r.WinRate = float64(r.Wins) / float64(r.Picks)
		out = append(out, r)
	}
	return out, rs.Err()
}
