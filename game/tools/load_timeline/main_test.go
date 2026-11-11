package main

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

const chromeUA = "Mozilla/5.0 (Macintosh) AppleWebKit/537.36 (KHTML, like Gecko) " +
	"Chrome/140.0.0.0 Safari/537.36"

func newTestServer(t *testing.T, at time.Time) (srv *httptest.Server, outDir string) {
	t.Helper()
	dir := t.TempDir()
	outDir = filepath.Join(t.TempDir(), "results")
	files := map[string]string{
		"index.html": "<html><head><title>Party Quest</title></head><body></body></html>",
		"index.js":   "engine",
	}
	for name, body := range files {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	srv = httptest.NewServer(newHandler(dir, outDir, func() time.Time { return at }))
	t.Cleanup(srv.Close)
	return srv, outDir
}

func get(t *testing.T, url string) string {
	t.Helper()
	resp, err := http.Get(url)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("GET %s: %d %s", url, resp.StatusCode, body)
	}
	return string(body)
}

func TestThePageGetsTheScriptFirstInItsHead(t *testing.T) {
	srv, _ := newTestServer(t, time.Now())
	for _, path := range []string{"/", "/index.html?dev"} {
		page := get(t, srv.URL+path)
		want := "<html><head><script>" + timelineJS + "</script><title>Party Quest</title>"
		if !strings.HasPrefix(page, want) {
			t.Errorf("GET %s: page starts %.80q, want the script first in <head>", path, page)
		}
	}
}

func TestOtherFilesAreServedAsTheyAre(t *testing.T) {
	srv, _ := newTestServer(t, time.Now())
	if body := get(t, srv.URL+"/index.js"); body != "engine" {
		t.Errorf("index.js = %q, want it unchanged", body)
	}
}

func TestAReportIsSavedByBrowserAndAnsweredWithItsTable(t *testing.T) {
	at := time.Date(2026, 11, 10, 16, 30, 5, 0, time.UTC)
	srv, outDir := newTestServer(t, at)
	body := `{"user_agent": "` + chromeUA + `", "marks": {"bar_hidden": 900, "wasm_compiled": 400},
		"stalls": [[450, 650]]}`
	resp, err := http.Post(srv.URL+"/report", "application/json", strings.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	table, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK || !strings.Contains(string(table), "bar_hidden") {
		t.Fatalf("POST /report: %d %q, want 200 and the table", resp.StatusCode, table)
	}

	raw, err := os.ReadFile(filepath.Join(outDir, "chrome-20261110-163005.000.json"))
	if err != nil {
		t.Fatal(err)
	}
	var saved savedReport
	if err := json.Unmarshal(raw, &saved); err != nil {
		t.Fatal(err)
	}
	if len(saved.Stages) != 2 || saved.Stages[1].Name != "bar_hidden" ||
		saved.Stages[1].BlockedMS != 200 {
		t.Errorf("saved stages = %+v, want wasm_compiled then bar_hidden blocked 200 ms",
			saved.Stages)
	}
}

func TestABadReportIsRefusedAndNothingSaved(t *testing.T) {
	srv, outDir := newTestServer(t, time.Now())
	for _, body := range []string{`not json`, `{"marks": {}}`, `{"marks": {"a": 1}, "extra": 2}`} {
		resp, err := http.Post(srv.URL+"/report", "application/json", strings.NewReader(body))
		if err != nil {
			t.Fatal(err)
		}
		resp.Body.Close()
		if resp.StatusCode != http.StatusBadRequest {
			t.Errorf("POST %q: %d, want 400", body, resp.StatusCode)
		}
	}
	if _, err := os.Stat(outDir); !os.IsNotExist(err) {
		t.Errorf("results folder exists after only bad reports (err %v)", err)
	}
}

func TestBrowserName(t *testing.T) {
	for ua, want := range map[string]string{
		chromeUA: "chrome",
		"Mozilla/5.0 (Macintosh; rv:159.0) Gecko/20100101 Firefox/159.0":            "firefox",
		chromeUA + " Edg/140.0.0.0":                                                 "edge",
		"Mozilla/5.0 (Macintosh) AppleWebKit/605.1.15 Version/19.0 Safari/605.1.15": "safari",
		"curl/8.0": "other",
	} {
		if got := browserName(ua); got != want {
			t.Errorf("browserName(%q) = %q, want %q", ua, got, want)
		}
	}
}
