package main

import (
	"context"
	"errors"
	"fmt"
	"io/fs"
	"log/slog"
	"net"
	"net/http"
	"os"
	"time"
)

const (
	// restartedMsg is logged when a start follows a crash in the same
	// container. Must match the restart alert in deploy/grafana/alerts.yaml
	// and the line deploy/entrypoint.sh prints.
	restartedMsg = "restarted in the same container: the last start exited"
	// heartbeatMsg is logged every heartbeatInterval, so that silence means
	// the backend, or the log shipping, has stopped.
	heartbeatMsg = "heartbeat"
	// heartbeatInterval must stay well under the no-logs alert's window in
	// deploy/grafana/alerts.yaml. Untuned.
	heartbeatInterval = 10 * time.Minute
	// healthcheckTimeout bounds one health check; Docker's own timeout in
	// deploy/compose.yaml is longer. Untuned.
	healthcheckTimeout = 3 * time.Second
)

// healthcheck asks the backend listening on addr (such as ":8080") whether
// it is ready, and returns an error unless it answers 200. Docker runs it
// through the -healthcheck flag, since the image has no shell or curl.
func healthcheck(ctx context.Context, addr string) error {
	host, port, err := net.SplitHostPort(addr)
	if err != nil {
		return err
	}
	if host == "" {
		host = "localhost"
	}
	ctx, cancel := context.WithTimeout(ctx, healthcheckTimeout)
	defer cancel()
	url := "http://" + net.JoinHostPort(host, port) + "/ready"
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("%s answered %s", url, resp.Status)
	}
	return nil
}

// noteStart reports whether marker already exists, creating it if not. A
// container keeps its own files across a restart but a deploy makes a new
// container, so an existing marker means this start follows a crash.
func noteStart(marker string) (restarted bool, err error) {
	f, err := os.OpenFile(marker, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o600)
	if errors.Is(err, fs.ErrExist) {
		return true, nil
	}
	if err != nil {
		return false, err
	}
	return false, f.Close()
}

// heartbeat logs heartbeatMsg every interval until ctx is done.
func heartbeat(ctx context.Context, log *slog.Logger, interval time.Duration) {
	t := time.NewTicker(interval)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			log.Info(heartbeatMsg)
		}
	}
}
