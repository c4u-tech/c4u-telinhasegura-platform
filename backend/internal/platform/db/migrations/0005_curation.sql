-- Curation: platform roles and the curation ledger.

CREATE TABLE platform_roles (
    account_id            uuid NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    role                  text NOT NULL CHECK (role IN ('admin', 'curator')),
    display_role          text,
    verified_professional boolean NOT NULL DEFAULT false,
    granted_by            uuid REFERENCES accounts (id) ON DELETE SET NULL, -- NULL: the server command
    granted_at            timestamptz NOT NULL,
    PRIMARY KEY (account_id, role),
    CHECK ((role = 'curator') = (display_role IS NOT NULL))
);
CREATE INDEX platform_roles_granted_by ON platform_roles (granted_by);

-- round is the round under review: the one new reviews join. published_round
-- is the round that last published the video, NULL until the first
-- publication. Publishing sets published_round to the round it ends and
-- moves round on, in the same statement; the new round is the revisit
-- that opens when review_due_at passes. A rejection holds the video
-- without touching published_round, so provenance is the
-- approvals of published_round whatever the video's state.
CREATE TABLE videos (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    youtube_id       text NOT NULL UNIQUE,
    title            text NOT NULL,
    channel_id       text NOT NULL,
    channel_title    text NOT NULL,
    duration_seconds integer NOT NULL,
    state            text NOT NULL CHECK (state IN ('pending', 'approved', 'held', 'removed')),
    round            integer NOT NULL DEFAULT 1,
    published_round  integer, -- NULL until the video is first published
    theme            text,
    min_age_band     text CHECK (min_age_band IN ('ate-4', '5-8', '9-12')),
    last_reviewed_at timestamptz,
    review_due_at    timestamptz,
    created_at       timestamptz NOT NULL,
    updated_at       timestamptz NOT NULL
);
CREATE INDEX videos_state ON videos (state, updated_at);

CREATE TABLE video_suggestions (
    video_id     uuid NOT NULL REFERENCES videos (id) ON DELETE CASCADE,
    account_id   uuid NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    suggested_at timestamptz NOT NULL,
    PRIMARY KEY (video_id, account_id)
);
CREATE INDEX video_suggestions_account ON video_suggestions (account_id, suggested_at);

-- A ledger: no path updates or deletes a review; only a video's deletion
-- cascades. A removed or erased curator's reviews keep the displayed-role
-- snapshot.
CREATE TABLE video_reviews (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    video_id     uuid NOT NULL REFERENCES videos (id) ON DELETE CASCADE,
    round        integer NOT NULL,
    curator_id   uuid REFERENCES accounts (id) ON DELETE SET NULL,
    display_role text NOT NULL,
    decision     text NOT NULL CHECK (decision IN ('approve', 'reject')),
    theme        text,
    min_age_band text,
    reason       text,
    reviewed_at  timestamptz NOT NULL,
    UNIQUE (video_id, round, curator_id)
);
CREATE INDEX video_reviews_curator ON video_reviews (curator_id);
