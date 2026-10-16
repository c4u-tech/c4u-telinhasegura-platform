-- Catalogue: the family adjustments (hides, reports) and the
-- thumbnail cache.

-- Why a held video is held, and where report counting restarts.
ALTER TABLE videos
    ADD COLUMN held_reason text CHECK (held_reason IN ('review','reports','unavailable')),
    ADD COLUMN reopened_at timestamptz;

-- Before this, a video was held only on a rejection.
UPDATE videos SET held_reason = 'review' WHERE state = 'held';

ALTER TABLE videos ADD CONSTRAINT videos_held_has_reason CHECK (state <> 'held' OR held_reason IS NOT NULL);

-- A guardian's hide of a video for one child.
CREATE TABLE video_hides (
    minor_id   uuid NOT NULL REFERENCES minors (id) ON DELETE CASCADE,
    video_id   uuid NOT NULL REFERENCES videos (id) ON DELETE CASCADE,
    hidden_by  uuid REFERENCES accounts (id) ON DELETE SET NULL,
    hidden_at  timestamptz NOT NULL,
    PRIMARY KEY (minor_id, video_id)
);

CREATE INDEX video_hides_hidden_by ON video_hides (hidden_by);

-- One report per family per video. An erased author leaves the
-- reason so the family's report still counts.
CREATE TABLE video_reports (
    video_id    uuid NOT NULL REFERENCES videos (id) ON DELETE CASCADE,
    family_id   uuid NOT NULL REFERENCES families (id) ON DELETE CASCADE,
    account_id  uuid REFERENCES accounts (id) ON DELETE SET NULL,
    reason      text NOT NULL CHECK (reason IN ('inadequado','assustador','publicidade','outro')),
    note        text,
    reported_at timestamptz NOT NULL,
    PRIMARY KEY (video_id, family_id)
);

CREATE INDEX video_reports_family ON video_reports (family_id);
CREATE INDEX video_reports_account ON video_reports (account_id);

-- Thumbnails fetched from YouTube's image host, stored only on success.
CREATE TABLE video_thumbnails (
    video_id   uuid PRIMARY KEY REFERENCES videos (id) ON DELETE CASCADE,
    bytes      bytea NOT NULL,
    fetched_at timestamptz NOT NULL
);
