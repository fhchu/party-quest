package main

import (
	"encoding/json"
	"os"
	"regexp"
	"strconv"
	"testing"
	"time"
)

// minHeartbeatsPerSilence is how many heartbeats the no-logs alert's window
// must span, so one late heartbeat doesn't raise it. Untuned.
const minHeartbeatsPerSilence = 2

func TestSilenceAlertSpansSeveralHeartbeats(t *testing.T) {
	raw, err := os.ReadFile("../../../deploy/grafana/alerts.json")
	if err != nil {
		t.Fatal(err)
	}
	var file struct {
		Rules []struct {
			UID  string `json:"uid"`
			Expr string `json:"expr"`
		} `json:"rules"`
	}
	if err := json.Unmarshal(raw, &file); err != nil {
		t.Fatal(err)
	}
	minutes := regexp.MustCompile(`\[(\d+)m\]`)
	for _, r := range file.Rules {
		if r.UID != "pq-backend-silent" {
			continue
		}
		m := minutes.FindStringSubmatch(r.Expr)
		if m == nil {
			t.Fatalf("no [Nm] window in %q", r.Expr)
		}
		n, err := strconv.Atoi(m[1])
		if err != nil {
			t.Fatal(err)
		}
		window := time.Duration(n) * time.Minute
		if want := minHeartbeatsPerSilence * heartbeatInterval; window < want {
			t.Fatalf("silence window %v, want at least %v", window, want)
		}
		return
	}
	t.Fatal("no pq-backend-silent rule in alerts.json")
}
