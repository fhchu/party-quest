package main

import (
	"reflect"
	"testing"
)

func TestStagesRunInTimeOrderEachFromTheOneBefore(t *testing.T) {
	got := stagesBetween(map[string]float64{
		"bar_hidden": 900, "wasm_downloaded": 300, "first_datagram": 1500,
	}, nil)
	want := []stage{
		{Name: "wasm_downloaded", StartMS: 0, EndMS: 300},
		{Name: "bar_hidden", StartMS: 300, EndMS: 900},
		{Name: "first_datagram", StartMS: 900, EndMS: 1500},
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("stages = %+v, want %+v", got, want)
	}
}

func TestAStallCountsInEachStageItOverlapsByTheOverlap(t *testing.T) {
	got := stagesBetween(map[string]float64{"a": 100, "b": 200, "c": 300},
		[][2]float64{{50, 150}, {250, 260}})
	for i, want := range []float64{50, 50, 10} {
		if got[i].BlockedMS != want {
			t.Errorf("stage %s blocked %v ms, want %v", got[i].Name, got[i].BlockedMS, want)
		}
	}
}

func TestMarksAtTheSameTimeKeepOneOrder(t *testing.T) {
	marks := map[string]float64{"b": 100, "a": 100, "c": 100}
	first := stagesBetween(marks, nil)
	for range 20 {
		if got := stagesBetween(marks, nil); !reflect.DeepEqual(got, first) {
			t.Fatalf("order changed between runs: %+v then %+v", first, got)
		}
	}
}
