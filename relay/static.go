package main

import (
	"mime"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"strconv"
	"strings"
)

// noBrotliText answers a browser that doesn't accept brotli. Every current
// browser does over HTTPS and on localhost.
const noBrotliText = "Your browser is incompatible. Try using an updated version of Google Chrome.\n"

// staticHandler serves the web export in dir, brotli-compressed only: a
// request for name is answered with name.br, and a browser that doesn't
// accept brotli gets 406 Not Acceptable.
//
// Every response must be revalidated (no-cache): Godot's export file names
// aren't content-hashed, so a cached file from an old build could otherwise
// run against a newer server. Revalidating costs one request per file per
// load, answered with 304 when nothing changed.
func staticHandler(dir string) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-cache")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Vary", "Accept-Encoding")
		if !accepts(r.Header.Get("Accept-Encoding"), "br") {
			http.Error(w, noBrotliText, http.StatusNotAcceptable)
			return
		}
		if !serveBrotli(w, r, dir) {
			http.NotFound(w, r)
		}
	})
}

// accepts reports whether an Accept-Encoding header allows encoding. A
// weight of q=0 refuses it.
func accepts(header, encoding string) bool {
	for _, part := range strings.Split(header, ",") {
		name, params, _ := strings.Cut(part, ";")
		if !strings.EqualFold(strings.TrimSpace(name), encoding) {
			continue
		}
		for _, param := range strings.Split(params, ";") {
			key, value, ok := strings.Cut(strings.TrimSpace(param), "=")
			if ok && strings.EqualFold(key, "q") {
				q, err := strconv.ParseFloat(value, 64)
				return err == nil && q > 0
			}
		}
		return true
	}
	return false
}

// serveBrotli sends the brotli copy of the requested file (name.br, as
// deploy/export-web.sh writes it), if there is one, and reports whether it
// did.
func serveBrotli(w http.ResponseWriter, r *http.Request, dir string) bool {
	name := path.Clean("/" + r.URL.Path)
	if strings.HasSuffix(r.URL.Path, "/") {
		name = path.Join(name, "index.html")
	}
	// path.Clean on a rooted path removes every "..", so this stays in dir.
	f, err := os.Open(filepath.Join(dir, filepath.FromSlash(name)+".br"))
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
	w.Header().Set("Content-Encoding", "br")
	http.ServeContent(w, r, name, info.ModTime(), f)
	return true
}
