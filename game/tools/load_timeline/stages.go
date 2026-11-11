package main

import (
	"fmt"
	"sort"
	"strings"
)

// stage is one step of the load: from the mark before it (or navigation
// start) to its own mark.
type stage struct {
	// Name is the mark that ends the stage.
	Name    string  `json:"stage"`
	StartMS float64 `json:"start_ms"`
	EndMS   float64 `json:"end_ms"`
	// BlockedMS is how much of the stage the main thread spent stalled.
	BlockedMS float64 `json:"blocked_ms"`
}

// stagesBetween turns marks (stage name to ms) into stages in time order,
// each with the part of stalls that falls inside it.
func stagesBetween(marks map[string]float64, stalls [][2]float64) []stage {
	names := make([]string, 0, len(marks))
	for name := range marks {
		names = append(names, name)
	}
	sort.Slice(names, func(i, j int) bool {
		if marks[names[i]] != marks[names[j]] {
			return marks[names[i]] < marks[names[j]]
		}
		return names[i] < names[j]
	})
	stages := make([]stage, 0, len(names))
	start := 0.0
	for _, name := range names {
		s := stage{Name: name, StartMS: start, EndMS: marks[name]}
		for _, stall := range stalls {
			s.BlockedMS += max(0, min(s.EndMS, stall[1])-max(s.StartMS, stall[0]))
		}
		stages = append(stages, s)
		start = s.EndMS
	}
	return stages
}

func formatTable(stages []stage) string {
	var b strings.Builder
	b.WriteString("load timeline (blocked: main thread not answering)\n")
	for _, s := range stages {
		fmt.Fprintf(&b, "%-16s +%6.0f ms  blocked %6.0f ms  ends at %6.0f ms\n",
			s.Name, s.EndMS-s.StartMS, s.BlockedMS, s.EndMS)
	}
	return b.String()
}
