package httpapi_test

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"game/server/internal/httpapi"
)

type fakeDB struct{ err error }

func (f fakeDB) Ping(context.Context) error { return f.err }

func get(t *testing.T, h http.Handler, path string) *httptest.ResponseRecorder {
	t.Helper()
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, path, nil))
	return rec
}

func TestHealthIgnoresDatabase(t *testing.T) {
	h := httpapi.New(fakeDB{err: errors.New("db down")}).Handler()
	if rec := get(t, h, "/health"); rec.Code != http.StatusOK {
		t.Fatalf("/health = %d, want 200 even when the database is down", rec.Code)
	}
}

func TestReady(t *testing.T) {
	tests := []struct {
		name string
		err  error
		want int
	}{
		{"database up", nil, http.StatusOK},
		{"database down", errors.New("db down"), http.StatusServiceUnavailable},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			h := httpapi.New(fakeDB{err: tt.err}).Handler()
			if rec := get(t, h, "/ready"); rec.Code != tt.want {
				t.Fatalf("/ready = %d, want %d", rec.Code, tt.want)
			}
		})
	}
}

func TestMethodNotAllowed(t *testing.T) {
	h := httpapi.New(fakeDB{}).Handler()
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/health", nil))
	if rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("POST /health = %d, want 405", rec.Code)
	}
}
