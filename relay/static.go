package main

import (
	"mime"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"strings"
)

// staticHandler serves the web export in dir.
//
// Every response must be revalidated (no-cache): Godot's export file names
// aren't content-hashed, so a cached file from an old build could otherwise
// run against a newer server. Revalidating costs one request per file per
// load, answered with 304 when nothing changed.
//
// When the browser accepts gzip and dir holds name.gz beside name (the deploy
// script makes them), the compressed copy is sent. The engine's .wasm is
// about four times smaller that way.
func staticHandler(dir string) http.Handler {
	files := http.FileServer(http.Dir(dir))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-cache")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		if strings.Contains(r.Header.Get("Accept-Encoding"), "gzip") && serveGzip(w, r, dir) {
			return
		}
		files.ServeHTTP(w, r)
	})
}

// serveGzip sends the .gz copy of the requested file, if there is one, and
// reports whether it did.
func serveGzip(w http.ResponseWriter, r *http.Request, dir string) bool {
	name := path.Clean("/" + r.URL.Path)
	if strings.HasSuffix(r.URL.Path, "/") {
		name = path.Join(name, "index.html")
	}
	// path.Clean on a rooted path removes every "..", so this stays in dir.
	f, err := os.Open(filepath.Join(dir, filepath.FromSlash(name)+".gz"))
	if err != nil {
		return false
	}
	defer f.Close() //nolint:errcheck // Opened for reading: a failed close loses nothing.
	info, err := f.Stat()
	if err != nil || info.IsDir() {
		return false
	}
	if t := mime.TypeByExtension(path.Ext(name)); t != "" {
		w.Header().Set("Content-Type", t)
	}
	w.Header().Set("Content-Encoding", "gzip")
	w.Header().Add("Vary", "Accept-Encoding")
	http.ServeContent(w, r, name, info.ModTime(), f)
	return true
}
