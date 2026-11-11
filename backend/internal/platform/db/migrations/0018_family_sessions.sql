-- Family sessions: a guardian, with the family PIN, lets one child open
-- one long work once, within minutes; the child's beats keep where the
-- work stopped so the next session starts there.
-- Erasure is by cascade from minors; an erased guardian leaves the session
-- without its account.
CREATE TABLE family_sessions (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    minor_id   uuid NOT NULL REFERENCES minors (id) ON DELETE CASCADE,
    video_id   uuid NOT NULL REFERENCES videos (id) ON DELETE CASCADE,
    account_id uuid REFERENCES accounts (id) ON DELETE SET NULL, -- the guardian who started it
    created_at timestamptz NOT NULL,
    expires_at timestamptz NOT NULL,
    used_at    timestamptz -- set by the one open it allows
);
CREATE INDEX family_sessions_minor_video ON family_sessions (minor_id, video_id);
CREATE INDEX family_sessions_created ON family_sessions (created_at);

-- One resume point per child and work, kept no longer than the plays.
CREATE TABLE play_positions (
    minor_id         uuid NOT NULL REFERENCES minors (id) ON DELETE CASCADE,
    video_id         uuid NOT NULL REFERENCES videos (id) ON DELETE CASCADE,
    position_seconds integer NOT NULL CHECK (position_seconds >= 0),
    updated_at       timestamptz NOT NULL,
    PRIMARY KEY (minor_id, video_id)
);
CREATE INDEX play_positions_updated ON play_positions (updated_at);

-- A play opened on a family session: only its beats keep a position.
ALTER TABLE plays ADD COLUMN family boolean NOT NULL DEFAULT false;
