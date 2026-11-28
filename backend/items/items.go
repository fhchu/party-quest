package items

import (
	"encoding/json"
	"time"
)

// Item is one entry of items.json.
type Item struct {
	// ID is the item's stable ID, shared with the game's data.
	ID string `json:"id"`
	// Name is the display name.
	Name string `json:"name"`
	// DisabledAt is when the item was retired, or nil while it is in use.
	DisabledAt *time.Time `json:"disabled_at,omitempty"`
}

// All returns every item in items.json, retired ones included.
func All() ([]Item, error) {
	var all []Item
	if err := json.Unmarshal(raw, &all); err != nil {
		return nil, err
	}
	return all, nil
}
