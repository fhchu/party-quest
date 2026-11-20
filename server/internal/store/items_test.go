package store_test

import (
	"context"
	"database/sql"
	"testing"
	"time"

	"game/server/internal/store"
	"game/server/internal/testdb"
	"game/server/items"
)

type itemRow struct {
	name       string
	disabledAt sql.NullString
}

func itemRows(t *testing.T, sqlDB *sql.DB) map[string]itemRow {
	t.Helper()
	rows, err := sqlDB.QueryContext(context.Background(), `SELECT id, name, disabled_at FROM item`)
	if err != nil {
		t.Fatalf("query: %v", err)
	}
	defer rows.Close()
	got := map[string]itemRow{}
	for rows.Next() {
		var id string
		var r itemRow
		if err := rows.Scan(&id, &r.name, &r.disabledAt); err != nil {
			t.Fatalf("scan: %v", err)
		}
		got[id] = r
	}
	return got
}

func sync(t *testing.T, sqlDB *sql.DB, all ...items.Item) error {
	t.Helper()
	return store.New(sqlDB).SyncItems(context.Background(), all)
}

func TestSyncItemsAddsEveryItem(t *testing.T) {
	sqlDB := testdb.New(t)
	if err := sync(t, sqlDB, items.Item{ID: "gold", Name: "Gold"}, items.Item{ID: "potion", Name: "Potion"}); err != nil {
		t.Fatalf("sync: %v", err)
	}
	got := itemRows(t, sqlDB)
	if len(got) != 2 || got["gold"].name != "Gold" || got["potion"].name != "Potion" {
		t.Fatalf("items = %v, want gold and potion", got)
	}
}

func TestSyncItemsTwiceAddsNothing(t *testing.T) {
	sqlDB := testdb.New(t)
	gold := items.Item{ID: "gold", Name: "Gold"}
	for range 2 {
		if err := sync(t, sqlDB, gold); err != nil {
			t.Fatalf("sync: %v", err)
		}
	}
	if got := itemRows(t, sqlDB); len(got) != 1 {
		t.Fatalf("items = %v, want one", got)
	}
}

func TestSyncItemsUpdatesNameAndDisabledTime(t *testing.T) {
	sqlDB := testdb.New(t)
	if err := sync(t, sqlDB, items.Item{ID: "potion", Name: "Potion"}); err != nil {
		t.Fatalf("first sync: %v", err)
	}
	retired := time.Date(2026, 11, 17, 21, 4, 5, 0, time.FixedZone("PST", -8*60*60))
	if err := sync(t, sqlDB, items.Item{ID: "potion", Name: "Old potion", DisabledAt: &retired}); err != nil {
		t.Fatalf("second sync: %v", err)
	}
	got := itemRows(t, sqlDB)["potion"]
	want := retired.UTC().Format("2006-01-02T15:04:05.000Z")
	if got.name != "Old potion" || got.disabledAt.String != want {
		t.Fatalf("potion = %+v, want Old potion disabled at %s", got, want)
	}
}

func TestSyncItemsRefusesAnItemMissingFromTheList(t *testing.T) {
	sqlDB := testdb.New(t)
	if err := sync(t, sqlDB, items.Item{ID: "gold", Name: "Gold"}, items.Item{ID: "potion", Name: "Potion"}); err != nil {
		t.Fatalf("first sync: %v", err)
	}
	if err := sync(t, sqlDB, items.Item{ID: "gold", Name: "Gold"}); err == nil {
		t.Fatal("sync without potion succeeded, want an error")
	}
}
