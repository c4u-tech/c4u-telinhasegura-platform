-- A moderator's viewing of a held video: when the player reached its end
-- for them in the video's current round. Publishing a doubt needs it, so a
-- video a curator was unsure of is still watched to the end by two people.

-- Doubts are decided under the moderator role, or the admin role for an
-- account without it, so a view keeps the role it was recorded under and
-- hangs off that role row: losing the role, a suspension and an account
-- erasure all remove it in one rule. The round's close removes it too.
CREATE TABLE moderator_views (
    moderator_id     uuid NOT NULL,
    role             text NOT NULL CHECK (role IN ('moderator', 'admin')),
    video_id         uuid NOT NULL REFERENCES videos (id) ON DELETE CASCADE,
    round            integer NOT NULL,
    played_to_end_at timestamptz NOT NULL,
    PRIMARY KEY (moderator_id, video_id, round),
    FOREIGN KEY (moderator_id, role) REFERENCES platform_roles (account_id, role) ON DELETE CASCADE
);
CREATE INDEX moderator_views_video ON moderator_views (video_id);
