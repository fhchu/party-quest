package items_test

import (
	"testing"

	"game/server/items"
)

func TestEveryItemHasAUniqueIDAndAName(t *testing.T) {
	all, err := items.All()
	if err != nil {
		t.Fatalf("read items.json: %v", err)
	}
	seen := map[string]bool{}
	for _, it := range all {
		if it.ID == "" || it.Name == "" {
			t.Errorf("item %+v needs an id and a name", it)
		}
		if seen[it.ID] {
			t.Errorf("item %q is listed twice", it.ID)
		}
		seen[it.ID] = true
	}
}
