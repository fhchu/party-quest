package main

import (
	"context"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func serve(t *testing.T, status int) string {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/ready" {
			http.NotFound(w, r)
			return
		}
		w.WriteHeader(status)
	}))
	t.Cleanup(srv.Close)
	return strings.TrimPrefix(srv.URL, "http://")
}

func TestHealthcheckPassesWhenReady(t *testing.T) {
	if err := healthcheck(context.Background(), serve(t, http.StatusOK)); err != nil {
		t.Fatal(err)
	}
}

func TestHealthcheckFailsWhenNotReady(t *testing.T) {
	if err := healthcheck(context.Background(), serve(t, http.StatusServiceUnavailable)); err == nil {
		t.Fatal("want an error for 503")
	}
}

func TestHealthcheckFailsWhenNothingListens(t *testing.T) {
	srv := httptest.NewServer(http.NotFoundHandler())
	addr := strings.TrimPrefix(srv.URL, "http://")
	srv.Close()
	if err := healthcheck(context.Background(), addr); err == nil {
		t.Fatal("want an error with nothing listening")
	}
}

func TestNoteStartIsFalseOnceThenTrue(t *testing.T) {
	marker := filepath.Join(t.TempDir(), "started")
	for i, want := range []bool{false, true, true} {
		got, err := noteStart(marker)
		if err != nil {
			t.Fatal(err)
		}
		if got != want {
			t.Fatalf("start %d: restarted = %v, want %v", i+1, got, want)
		}
	}
}

type lines struct{ n chan string }

func (l lines) Write(p []byte) (int, error) {
	l.n <- string(p)
	return len(p), nil
}

func TestHeartbeatLogsUntilCancelled(t *testing.T) {
	out := lines{make(chan string, 8)}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		heartbeat(ctx, slog.New(slog.NewTextHandler(out, nil)), time.Millisecond)
		close(done)
	}()
	if line := <-out.n; !strings.Contains(line, heartbeatMsg) {
		t.Fatalf("got %q, want a heartbeat", line)
	}
	cancel()
	<-done
}
