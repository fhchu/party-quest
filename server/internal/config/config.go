// Package config reads server settings from environment variables.
package config

import (
	"errors"
	"fmt"
	"os"
	"strconv"
)

// defaultAddr is ADDR when it isn't set. Any free port would do;
// .env.example repeats it.
const defaultAddr = ":8080"

// Config holds the server's settings.
type Config struct {
	// Addr is the HTTP listen address, such as ":8080".
	Addr string
	// DatabaseURL is a Postgres connection URL.
	DatabaseURL string
	// AutoMigrate applies pending migrations at startup.
	AutoMigrate bool
}

// Load reads DATABASE_URL (required), ADDR (default [defaultAddr]) and
// AUTO_MIGRATE (default true, so a fresh database works without a separate
// migrate step).
func Load() (Config, error) {
	cfg := Config{
		Addr:        getenv("ADDR", defaultAddr),
		DatabaseURL: os.Getenv("DATABASE_URL"),
		AutoMigrate: true,
	}
	if v := os.Getenv("AUTO_MIGRATE"); v != "" {
		b, err := strconv.ParseBool(v)
		if err != nil {
			return Config{}, fmt.Errorf("AUTO_MIGRATE must be a boolean (got %q): %w", v, err)
		}
		cfg.AutoMigrate = b
	}
	if cfg.DatabaseURL == "" {
		return Config{}, errors.New("DATABASE_URL is required")
	}
	return cfg, nil
}

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
