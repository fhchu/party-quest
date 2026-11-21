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
	// DatabasePath is the SQLite database file, created if missing.
	DatabasePath string
	// AutoMigrate applies pending migrations at startup.
	AutoMigrate bool
	// GameServerToken is the secret the game server sends to submit runs.
	GameServerToken string
	// StartMarker is a file the first start in a container creates, so a
	// later start in the same container is known to follow a crash. Empty
	// skips the check; only the container sets it.
	StartMarker string
}

// Load reads DATABASE_PATH and GAME_SERVER_TOKEN (both required), ADDR
// (default [defaultAddr]), AUTO_MIGRATE (default true, so a fresh
// database works without a separate migrate step) and START_MARKER
// (optional).
func Load() (Config, error) {
	cfg := Config{
		Addr:            getenv("ADDR", defaultAddr),
		DatabasePath:    os.Getenv("DATABASE_PATH"),
		AutoMigrate:     true,
		GameServerToken: os.Getenv("GAME_SERVER_TOKEN"),
		StartMarker:     os.Getenv("START_MARKER"),
	}
	if v := os.Getenv("AUTO_MIGRATE"); v != "" {
		b, err := strconv.ParseBool(v)
		if err != nil {
			return Config{}, fmt.Errorf("AUTO_MIGRATE must be a boolean (got %q): %w", v, err)
		}
		cfg.AutoMigrate = b
	}
	if cfg.DatabasePath == "" {
		return Config{}, errors.New("DATABASE_PATH is required")
	}
	if cfg.GameServerToken == "" {
		return Config{}, errors.New("GAME_SERVER_TOKEN is required")
	}
	return cfg, nil
}

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
