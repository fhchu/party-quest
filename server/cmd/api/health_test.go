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
	steps := []struct {
		name          string
		wantRestarted bool
	}{
		{"first start", false},
		{"second start", true},
		{"third start", true},
	}
	for _, step := range steps {
		t.Run(step.name, func(t *testing.T) {
			got, err := noteStart(marker)
			if err != nil {
				t.Fatal(err)
			}
			if got != step.wantRestarted {
				t.Errorf("restarted = %v, want %v", got, step.wantRestarted)
			}
		})
	}
}

// logLines collects each line a slog handler writes.
type logLines struct{ written chan string }

func (l logLines) Write(p []byte) (int, error) {
	l.written <- string(p)
	return len(p), nil
}

func TestHeartbeatLogsAndStopsWhenCancelled(t *testing.T) {
	out := logLines{make(chan string, 8)}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		heartbeat(ctx, slog.New(slog.NewTextHandler(out, nil)), time.Millisecond)
		close(done)
	}()
	// Spelled out rather than read from heartbeatMsg, so an empty message fails.
	if line := <-out.written; !strings.Contains(line, "msg=heartbeat") {
		t.Fatalf("got %q, want a heartbeat line", line)
	}
	cancel()
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("heartbeat still running after cancel")
	}
}
