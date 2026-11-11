// Command load_timeline serves a Godot web export with a script that times
// each stage of the page's load, then saves what each browser reports.
//
// Usage, from this folder:
//
//	go run . [-addr 127.0.0.1:8070] [-out results] EXPORT_DIR
//
// EXPORT_DIR holds an uncompressed export (index.html, index.wasm, ...).
// Open the address in each browser; the game needs the game server and
// relay running (dev.sh) to get past connecting. Each load is saved as
// OUT/<browser>-<time>.json and logged as a table in the page's console.
package main

import (
	_ "embed"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// timelineJS is injected into the page's <head>, so it runs before the
// engine loads.
//
//go:embed timeline.js
var timelineJS string

// maxReportBytes bounds a posted report: a few dozen marks and stalls.
const maxReportBytes = 1 << 20

// report is what the page posts once loading is over.
type report struct {
	UserAgent string `json:"user_agent"`
	// Marks maps each stage to when it ended, in ms since navigation start.
	Marks map[string]float64 `json:"marks"`
	// Stalls are [start, end] ms spans when the main thread didn't answer.
	Stalls [][2]float64 `json:"stalls"`
}

// savedReport is a report as written to disk, with its stages worked out.
type savedReport struct {
	report
	Browser string  `json:"browser"`
	Stages  []stage `json:"stages"`
}

func main() {
	addr := flag.String("addr", "127.0.0.1:8070", "address to serve on")
	out := flag.String("out", "results", "folder to save reports in")
	flag.Parse()
	if flag.NArg() != 1 {
		fmt.Fprintln(os.Stderr, "usage: load_timeline [-addr host:port] [-out dir] EXPORT_DIR")
		os.Exit(2)
	}
	dir := flag.Arg(0)
	if _, err := os.Stat(filepath.Join(dir, "index.html")); err != nil {
		log.Fatalf("%s needs an uncompressed web export: %v", dir, err)
	}
	log.Printf("serving %s at http://%s, saving reports in %s", dir, *addr, *out)
	log.Fatal(http.ListenAndServe(*addr, newHandler(dir, *out, time.Now)))
}

// newHandler serves the export in dir with timelineJS in its index.html,
// and saves each posted report in outDir, named by browser and now().
func newHandler(dir, outDir string, now func() time.Time) http.Handler {
	files := http.FileServer(http.Dir(dir))
	index := func(w http.ResponseWriter, _ *http.Request) {
		serveIndex(w, filepath.Join(dir, "index.html"))
	}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /{$}", index)
	// FileServer would redirect this to /, which loses the query string.
	mux.HandleFunc("GET /index.html", index)
	mux.HandleFunc("GET /", func(w http.ResponseWriter, r *http.Request) {
		// Exports aren't content-hashed: a cached file from an earlier build
		// would run against this one.
		w.Header().Set("Cache-Control", "no-cache")
		files.ServeHTTP(w, r)
	})
	mux.HandleFunc("POST /report", func(w http.ResponseWriter, r *http.Request) {
		saveReport(w, r, outDir, now())
	})
	return mux
}

func serveIndex(w http.ResponseWriter, path string) {
	page, err := os.ReadFile(path)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	head, rest, found := strings.Cut(string(page), "<head>")
	if !found {
		http.Error(w, path+" has no <head> to put the timeline script in",
			http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-cache")
	// A browser gone mid-response is nothing to act on.
	_, _ = fmt.Fprintf(w, "%s<head><script>%s</script>%s", head, timelineJS, rest)
}

// saveReport writes the posted report to outDir and answers with its table,
// which the page logs.
func saveReport(w http.ResponseWriter, r *http.Request, outDir string, at time.Time) {
	var rep report
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxReportBytes))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&rep); err != nil {
		http.Error(w, "bad report: "+err.Error(), http.StatusBadRequest)
		return
	}
	if len(rep.Marks) == 0 {
		http.Error(w, "bad report: no marks", http.StatusBadRequest)
		return
	}
	saved := savedReport{
		report:  rep,
		Browser: browserName(rep.UserAgent),
		Stages:  stagesBetween(rep.Marks, rep.Stalls),
	}
	body, err := json.MarshalIndent(saved, "", "\t")
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	name := fmt.Sprintf("%s-%s.json", saved.Browser, at.Format("20060102-150405.000"))
	path := filepath.Join(outDir, name)
	if err := os.MkdirAll(outDir, 0o755); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	if err := os.WriteFile(path, body, 0o644); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	table := formatTable(saved.Stages)
	log.Printf("saved %s\n%s", path, table)
	_, _ = fmt.Fprint(w, table)
}

// browserName names the browser a user agent string comes from. Order
// matters: Edge's says Chrome and Safari too, and Chrome's says Safari.
func browserName(userAgent string) string {
	for _, b := range []struct{ token, name string }{
		{"Firefox/", "firefox"},
		{"Edg/", "edge"},
		{"Chrome/", "chrome"},
		{"Safari/", "safari"},
	} {
		if strings.Contains(userAgent, b.token) {
			return b.name
		}
	}
	return "other"
}
