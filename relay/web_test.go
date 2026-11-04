package main

import (
	"bytes"
	"compress/gzip"
	"crypto/tls"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

const testPage = "<html>game</html>"

// exportDir writes a small stand-in for the web export: index.html, a .wasm
// with a gzipped copy, and a file outside the directory that must stay
// unreachable.
func exportDir(t *testing.T) string {
	t.Helper()
	parent := t.TempDir()
	dir := filepath.Join(parent, "web")
	if err := os.Mkdir(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	var gz bytes.Buffer
	zw := gzip.NewWriter(&gz)
	if _, err := zw.Write([]byte("wasm")); err != nil {
		t.Fatal(err)
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	files := map[string][]byte{
		filepath.Join(dir, "index.html"):       []byte(testPage),
		filepath.Join(dir, "index.wasm"):       []byte("wasm"),
		filepath.Join(dir, "index.wasm.gz"):    gz.Bytes(),
		filepath.Join(parent, "secret.txt"):    []byte("secret"),
		filepath.Join(parent, "secret.txt.gz"): gz.Bytes(),
	}
	for name, data := range files {
		if err := os.WriteFile(name, data, 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return dir
}

func get(h http.Handler, path string, header http.Header) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodGet, path, nil)
	for k, v := range header {
		req.Header[k] = v
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

func TestStaticServesTheExportUncached(t *testing.T) {
	h := webHandler(exportDir(t), "")
	rec := get(h, "/", nil)
	if rec.Code != http.StatusOK || rec.Body.String() != testPage {
		t.Fatalf("GET / = %d %q, want 200 and the page", rec.Code, rec.Body)
	}
	if got := rec.Header().Get("Cache-Control"); got != "no-cache" {
		t.Errorf("Cache-Control = %q, want no-cache", got)
	}
	if got := rec.Header().Get("X-Content-Type-Options"); got != "nosniff" {
		t.Errorf("X-Content-Type-Options = %q, want nosniff", got)
	}
}

func TestStaticSendsGzipOnlyWhenAccepted(t *testing.T) {
	h := webHandler(exportDir(t), "")

	rec := get(h, "/index.wasm", http.Header{"Accept-Encoding": {"gzip, br"}})
	if rec.Header().Get("Content-Encoding") != "gzip" {
		t.Fatalf("Content-Encoding = %q, want gzip", rec.Header().Get("Content-Encoding"))
	}
	if got := rec.Header().Get("Content-Type"); got != "application/wasm" {
		t.Errorf("Content-Type = %q, want application/wasm (browsers compile only that)", got)
	}
	zr, err := gzip.NewReader(rec.Body)
	if err != nil {
		t.Fatal(err)
	}
	if body, _ := io.ReadAll(zr); string(body) != "wasm" {
		t.Errorf("unzipped body = %q, want wasm", body)
	}

	rec = get(h, "/index.wasm", nil)
	if rec.Header().Get("Content-Encoding") != "" || rec.Body.String() != "wasm" {
		t.Errorf("without gzip: encoding %q, body %q; want the plain file",
			rec.Header().Get("Content-Encoding"), rec.Body)
	}
}

func TestStaticStaysInItsDirectory(t *testing.T) {
	h := webHandler(exportDir(t), "")
	for _, header := range []http.Header{nil, {"Accept-Encoding": {"gzip"}}} {
		rec := get(h, "/../secret.txt", header)
		if rec.Code == http.StatusOK {
			t.Fatalf("GET /../secret.txt (Accept-Encoding %q) = 200, want it refused",
				header.Get("Accept-Encoding"))
		}
	}
}

func TestCertHashOnlyWithASelfSignedCertificate(t *testing.T) {
	if rec := get(webHandler("", "abc="), "/cert-hash", nil); rec.Body.String() != "abc=" {
		t.Errorf("with a hash: /cert-hash = %d %q, want abc=", rec.Code, rec.Body)
	}
	if rec := get(webHandler("", ""), "/cert-hash", nil); rec.Code != http.StatusNotFound {
		t.Errorf("without a hash: /cert-hash = %d, want 404", rec.Code)
	}
}

func TestWebSideServesHTTPS(t *testing.T) {
	c, err := loadCerts("", "", "", "")
	if err != nil {
		t.Fatal(err)
	}
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	srv := webServer("", webHandler(exportDir(t), ""))
	srv.TLSConfig = c.tls
	go func() { _ = srv.ServeTLS(ln, "", "") }()
	t.Cleanup(func() { srv.Close() })

	client := &http.Client{Transport: &http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	}}
	resp, err := client.Get("https://" + ln.Addr().String() + "/")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if body, _ := io.ReadAll(resp.Body); resp.StatusCode != http.StatusOK || string(body) != testPage {
		t.Fatalf("GET / over TLS = %d %q, want 200 and the page", resp.StatusCode, body)
	}
}

func TestDomainRedirectsPlainHTTP(t *testing.T) {
	c, err := loadCerts("play.example", t.TempDir(), "", "")
	if err != nil {
		t.Fatal(err)
	}
	rec := get(c.acme.HTTPHandler(nil), "http://play.example/index.html", nil)
	if rec.Code != http.StatusFound || rec.Header().Get("Location") != "https://play.example/index.html" {
		t.Fatalf("GET over HTTP = %d to %q, want 302 to https://play.example/index.html",
			rec.Code, rec.Header().Get("Location"))
	}
}

func TestOriginCheck(t *testing.T) {
	site := "https://play.example"
	tests := []struct {
		name    string
		allowed []string
		origin  string
		want    bool
	}{
		{"the game's site", []string{site}, site, true},
		{"another site", []string{site}, "https://evil.example", false},
		{"same host, another port", []string{site}, site + ":8443", false},
		{"no Origin (not a browser)", []string{site}, "", true},
		{"localhost when testing", nil, "http://localhost:8060", true},
		{"loopback IP when testing", nil, "http://127.0.0.1:18061", true},
		{"IPv6 loopback when testing", nil, "http://[::1]:8060", true},
		{"another site when testing", nil, "https://evil.example", false},
		{"a hostname containing localhost", nil, "https://localhost.evil.example", false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			r := httptest.NewRequest(http.MethodGet, "/match", nil)
			if tt.origin != "" {
				r.Header.Set("Origin", tt.origin)
			}
			if got := checkOrigin(tt.allowed)(r); got != tt.want {
				t.Fatalf("checkOrigin(%v) for %q = %v, want %v", tt.allowed, tt.origin, got, tt.want)
			}
		})
	}
}

func TestOriginFlagWantsABareOrigin(t *testing.T) {
	for _, v := range []string{"play.example", "https://play.example/game", "https://"} {
		var o originList
		if err := o.Set(v); err == nil {
			t.Errorf("Set(%q) succeeded, want an error", v)
		}
	}
	var o originList
	if err := o.Set("https://play.example/"); err != nil || o[0] != "https://play.example" {
		t.Errorf("Set(https://play.example/) = %v, %v; want https://play.example", o, err)
	}
}

func TestRelayRefusesOtherSites(t *testing.T) {
	gameAddr, _ := fakeGame(t)
	if _, err := dialRelayFrom(t, gameAddr, "https://evil.example"); err == nil {
		t.Fatal("a page from another site connected, want it refused")
	}
}
