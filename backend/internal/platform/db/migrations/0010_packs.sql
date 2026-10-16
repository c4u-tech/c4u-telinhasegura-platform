-- Pacotinhos: the packs.

-- round: the round under review. published_round: the round whose
-- composition children get, NULL until first published. A recompose
-- moves round on; publishing sets published_round = round. Removal is
-- final (no reopen).
CREATE TABLE packs (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    state            text NOT NULL CHECK (state IN ('pending','approved','held','removed')),
    round            integer NOT NULL DEFAULT 1,
    published_round  integer,
    theme            text,                 -- curation surfaces only
    last_reviewed_at timestamptz,
    created_at       timestamptz NOT NULL,
    updated_at       timestamptz NOT NULL,
    CHECK (state <> 'approved' OR published_round IS NOT NULL)
);
CREATE INDEX packs_state ON packs (state, updated_at);

-- One composition per round: title, cover and composer belong to it, and
-- no path updates it. Only packs.round is ever reviewed: a round a
-- recompose replaced before its outcome keeps 'open'.
CREATE TABLE pack_rounds (
    pack_id        uuid NOT NULL REFERENCES packs (id) ON DELETE CASCADE,
    round          integer NOT NULL,
    title          text NOT NULL,
    cover_video_id uuid NOT NULL REFERENCES videos (id),
    composer_id    uuid REFERENCES accounts (id) ON DELETE SET NULL,
    composer_role  text NOT NULL,          -- displayed-role snapshot
    composed_at    timestamptz NOT NULL,
    outcome        text NOT NULL DEFAULT 'open' CHECK (outcome IN ('open','published','rejected')),
    PRIMARY KEY (pack_id, round)
);
CREATE INDEX pack_rounds_composer ON pack_rounds (composer_id);

CREATE TABLE pack_items (
    pack_id  uuid NOT NULL,
    round    integer NOT NULL,
    position smallint NOT NULL CHECK (position BETWEEN 1 AND 5),
    video_id uuid NOT NULL REFERENCES videos (id),
    PRIMARY KEY (pack_id, round, position),
    UNIQUE (pack_id, round, video_id),
    FOREIGN KEY (pack_id, round) REFERENCES pack_rounds (pack_id, round) ON DELETE CASCADE
);
CREATE INDEX pack_items_video ON pack_items (video_id);

-- A ledger like video_reviews: an erased curator's reviews keep their
-- displayed-role snapshot.
CREATE TABLE pack_reviews (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    pack_id      uuid NOT NULL REFERENCES packs (id) ON DELETE CASCADE,
    round        integer NOT NULL,
    curator_id   uuid REFERENCES accounts (id) ON DELETE SET NULL,
    display_role text NOT NULL,
    decision     text NOT NULL CHECK (decision IN ('approve','reject')),
    reason       text,
    reviewed_at  timestamptz NOT NULL,
    UNIQUE (pack_id, round, curator_id)
);
CREATE INDEX pack_reviews_curator ON pack_reviews (curator_id);
