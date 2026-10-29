-- +goose Up

CREATE TABLE player (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    token_hash    BYTEA NOT NULL UNIQUE,
    currency      BIGINT NOT NULL DEFAULT 0,
    data          JSONB NOT NULL DEFAULT '{}',
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE match (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    balance_version  TEXT NOT NULL,
    status           TEXT NOT NULL DEFAULT 'in_progress'
                     CHECK (status IN ('in_progress', 'completed', 'abandoned')),
    outcome          TEXT CHECK (outcome IN ('win', 'loss')),
    started_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    ended_at         TIMESTAMPTZ,
    CHECK ((status = 'completed') = (outcome IS NOT NULL)),
    CHECK ((status = 'in_progress') = (ended_at IS NULL))
);

CREATE INDEX match_balance_version_idx ON match (balance_version, started_at);

CREATE TABLE match_participant (
    match_id      UUID NOT NULL REFERENCES match (id),
    player_id     UUID NOT NULL REFERENCES player (id),
    character_id  TEXT NOT NULL,
    stats         JSONB NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(stats) = 'object'),
    reward        BIGINT NOT NULL DEFAULT 0,
    PRIMARY KEY (match_id, player_id)
);

CREATE INDEX match_participant_character_idx ON match_participant (character_id);
CREATE INDEX match_participant_player_idx ON match_participant (player_id);

CREATE TABLE match_participant_item (
    match_id   UUID NOT NULL,
    player_id  UUID NOT NULL,
    item_id    TEXT NOT NULL,
    PRIMARY KEY (match_id, player_id, item_id),
    FOREIGN KEY (match_id, player_id) REFERENCES match_participant (match_id, player_id)
);

CREATE INDEX match_participant_item_item_idx ON match_participant_item (item_id);

-- +goose Down

DROP TABLE match_participant_item;
DROP TABLE match_participant;
DROP TABLE match;
DROP TABLE player;