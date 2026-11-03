// Package auth issues anonymous bearer tokens and resolves them to players.
// Only a SHA-256 hash of each token is stored.
package auth

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"errors"
	"net/http"
	"strings"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"game/server/internal/httpjson"
)

// NewToken returns a random token to give the client and the hash to store
// in player.token_hash. The token carries rand.Text's 128 bits or more, so
// it can't be guessed.
func NewToken() (token string, hash []byte) {
	token = rand.Text()
	return token, hashToken(token)
}

func hashToken(token string) []byte {
	sum := sha256.Sum256([]byte(token))
	return sum[:]
}

type ctxKey struct{}

// Require responds 401 unless the request carries a valid
// "Authorization: Bearer <token>" header, and otherwise calls next with the
// player's ID available through PlayerID.
func Require(pool *pgxpool.Pool, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		token, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
		if !ok || token == "" {
			httpjson.Error(w, http.StatusUnauthorized, "missing bearer token")
			return
		}
		var id uuid.UUID
		err := pool.QueryRow(r.Context(), `SELECT id FROM player WHERE token_hash = $1`, hashToken(token)).Scan(&id)
		if errors.Is(err, pgx.ErrNoRows) {
			httpjson.Error(w, http.StatusUnauthorized, "invalid token")
			return
		}
		if err != nil {
			httpjson.InternalError(w, r, err)
			return
		}
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), ctxKey{}, id)))
	})
}

// PlayerID returns the player authenticated by Require.
func PlayerID(ctx context.Context) (uuid.UUID, bool) {
	id, ok := ctx.Value(ctxKey{}).(uuid.UUID)
	return id, ok
}
