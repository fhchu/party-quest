package config

import (
	"errors"
	"fmt"
	"os"
	"strconv"
)

type Config struct {
	Addr        string
	DatabaseURL string
	AutoMigrate bool
}

func Load() (Config, error) {
	cfg := Config{
		Addr:        getenv("ADDR", ":8080"),
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
