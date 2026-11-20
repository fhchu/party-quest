-- +goose Up

-- Times are UTC text in one layout (store.timeLayout), so they sort and
-- compare in time order.

-- An account. Who someone is, apart from what they own.
CREATE TABLE player (
    id          TEXT PRIMARY KEY,
    created_at  TEXT NOT NULL
) STRICT;

-- Which login belongs to which account. subject is the provider's own user
-- ID, such as a Firebase UID.
CREATE TABLE player_login (
    provider    TEXT NOT NULL CHECK (provider IN ('firebase')),
    subject     TEXT NOT NULL,
    player_id   TEXT NOT NULL REFERENCES player (id),
    created_at  TEXT NOT NULL,
    PRIMARY KEY (provider, subject)
) STRICT;

CREATE INDEX player_login_player_idx ON player_login (player_id);

-- The items that exist, gold included. Filled from items/items.json at
-- startup. A retired item keeps its row, since ledger rows point at it.
CREATE TABLE item (
    id           TEXT PRIMARY KEY,
    name         TEXT NOT NULL,
    disabled_at  TEXT
) STRICT;

-- How many of each item a player has: always the sum of their ledger rows
-- for it. May go below 0 when an admin reverses a transaction.
CREATE TABLE inventory (
    player_id  TEXT NOT NULL REFERENCES player (id),
    item_id    TEXT NOT NULL REFERENCES item (id),
    count      INTEGER NOT NULL,
    PRIMARY KEY (player_id, item_id)
) STRICT;

-- A finished run. id is made by the game server, so a retried submission
-- finds the run it already stored.
CREATE TABLE run (
    id           TEXT PRIMARY KEY,
    outcome      TEXT NOT NULL CHECK (outcome IN ('won', 'lost', 'abandoned')),
    started_at   TEXT NOT NULL,
    ended_at     TEXT NOT NULL,
    received_at  TEXT NOT NULL,
    CHECK (ended_at >= started_at)
) STRICT;

-- Every change to a player's items. A run writes one net row per player and
-- item.
CREATE TABLE ledger (
    id          INTEGER PRIMARY KEY,
    player_id   TEXT NOT NULL REFERENCES player (id),
    item_id     TEXT NOT NULL REFERENCES item (id),
    amount      INTEGER NOT NULL CHECK (amount <> 0),
    reason      TEXT NOT NULL CHECK (reason IN ('run')),
    run_id      TEXT REFERENCES run (id),
    created_at  TEXT NOT NULL,
    CHECK ((reason = 'run') = (run_id IS NOT NULL)),
    UNIQUE (run_id, player_id, item_id)
) STRICT;

CREATE INDEX ledger_player_idx ON ledger (player_id);

-- +goose Down

DROP TABLE ledger;
DROP TABLE run;
DROP TABLE inventory;
DROP TABLE item;
DROP TABLE player_login;
DROP TABLE player;
