// Package auth guards routes that only services on the box may call.
package auth

import (
	"crypto/subtle"
	"net/http"
	"strings"

	"game/server/internal/httpjson"
)

// RequireToken responds 401 unless the request carries
// "Authorization: Bearer <token>", and otherwise calls next. The compare
// runs for the same time however much of the token matches, so timing can't
// reveal it.
func RequireToken(token string, next http.Handler) http.Handler {
	want := []byte(token)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		got, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
		if !ok || subtle.ConstantTimeCompare([]byte(got), want) != 1 {
			httpjson.Error(w, http.StatusUnauthorized, "missing or wrong token")
			return
		}
		next.ServeHTTP(w, r)
	})
}
