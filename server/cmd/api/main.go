// Command api serves the game backend over HTTP, configured by environment
// variables (see internal/config).
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"game/server/internal/config"
	"game/server/internal/db"
	"game/server/internal/httpapi"
	"game/server/internal/runs"
	"game/server/internal/store"
	"game/server/items"
)

const (
	// readHeaderTimeout stops a client that opens a connection and sends
	// headers slowly from holding it forever. Untuned.
	readHeaderTimeout = 5 * time.Second
	// shutdownTimeout is how long in-flight requests, such as a run
	// submission's transaction, get to finish on SIGTERM. Untuned.
	shutdownTimeout = 10 * time.Second
)

func main() {
	log := slog.New(slog.NewTextHandler(os.Stdout, nil))
	slog.SetDefault(log)
	if err := run(log); err != nil {
		log.Error("server stopped", "err", err)
		os.Exit(1)
	}
}

func run(log *slog.Logger) error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	sqlDB, err := db.Open(ctx, cfg.DatabasePath)
	if err != nil {
		return err
	}
	defer sqlDB.Close()

	if cfg.AutoMigrate {
		if err := db.Migrate(ctx, sqlDB); err != nil {
			return err
		}
		log.Info("migrations applied")
	}

	all, err := items.All()
	if err != nil {
		return fmt.Errorf("read items.json: %w", err)
	}
	st := store.New(sqlDB)
	if err := st.SyncItems(ctx, all); err != nil {
		return fmt.Errorf("sync items: %w", err)
	}

	srv := &http.Server{
		Addr:              cfg.Addr,
		Handler:           httpapi.New(sqlDB, runs.New(st, cfg.GameServerToken)).Handler(),
		ReadHeaderTimeout: readHeaderTimeout,
	}

	// Buffered so the goroutine can exit after a shutdown nobody reads it for.
	errCh := make(chan error, 1)
	go func() {
		log.Info("listening", "addr", cfg.Addr)
		errCh <- srv.ListenAndServe()
	}()

	select {
	case err := <-errCh:
		if !errors.Is(err, http.ErrServerClosed) {
			return err
		}
		return nil
	case <-ctx.Done():
		log.Info("shutting down")
		shutdownCtx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
		defer cancel()
		return srv.Shutdown(shutdownCtx)
	}
}
