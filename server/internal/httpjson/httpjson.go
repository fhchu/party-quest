// Package httpjson holds the JSON request and response helpers shared by the
// HTTP handlers.
package httpjson

import (
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
)

// maxBodyBytes caps a request body, so a client can't make the server read
// without end. Far above any real request: a 4-player match submission is a
// few kilobytes. Untuned.
const maxBodyBytes = 1 << 20

// Write sends v as JSON with the given status.
func Write(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	// The status is already sent, so a failed write can't be reported to the
	// client; it means the connection is gone.
	_ = json.NewEncoder(w).Encode(v)
}

// Error writes {"error": msg}.
func Error(w http.ResponseWriter, status int, msg string) {
	Write(w, status, map[string]string{"error": msg})
}

// InternalError logs err and writes a 500 without exposing its details.
func InternalError(w http.ResponseWriter, r *http.Request, err error) {
	slog.ErrorContext(r.Context(), "request failed", "method", r.Method, "path", r.URL.Path, "err", err)
	Error(w, http.StatusInternalServerError, "internal error")
}

// Decode reads a single JSON value of at most [maxBodyBytes] from the
// request body into v, rejecting unknown fields.
func Decode(w http.ResponseWriter, r *http.Request, v any) error {
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxBodyBytes))
	dec.DisallowUnknownFields()
	if err := dec.Decode(v); err != nil {
		return err
	}
	if err := dec.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return errors.New("body must contain a single JSON value")
	}
	return nil
}
