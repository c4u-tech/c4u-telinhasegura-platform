-- Screen time: per-child rules, the
-- family's zone, plays counted by beats, daily totals and extensions.
-- Erasure is by cascade from minors and families.
CREATE TABLE screentime_families (
    family_id uuid PRIMARY KEY REFERENCES families (id) ON DELETE CASCADE,
    time_zone text NOT NULL, -- IANA, checked by time.LoadLocation; set on the first save only
    set_at    timestamptz NOT NULL
);

CREATE TABLE screentime_rules (
    minor_id      uuid PRIMARY KEY REFERENCES minors (id) ON DELETE CASCADE,
    daily_minutes integer NOT NULL CHECK (daily_minutes BETWEEN 15 AND 240),
    window_start  integer NOT NULL CHECK (window_start BETWEEN 0 AND 1439), -- minutes after local midnight
    window_end    integer NOT NULL CHECK (window_end BETWEEN 1 AND 1439),
    updated_by    uuid REFERENCES accounts (id) ON DELETE SET NULL,
    updated_at    timestamptz NOT NULL,
    CHECK (window_start < window_end)
);

CREATE TABLE plays (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    minor_id     uuid NOT NULL REFERENCES minors (id) ON DELETE CASCADE,
    video_id     uuid NOT NULL REFERENCES videos (id) ON DELETE CASCADE,
    device_id    uuid REFERENCES devices (id) ON DELETE SET NULL,
    started_at   timestamptz NOT NULL,
    last_beat_at timestamptz NOT NULL,
    playing      boolean NOT NULL,
    seconds      integer NOT NULL DEFAULT 0
);
CREATE INDEX plays_started ON plays (started_at);
CREATE INDEX plays_minor ON plays (minor_id, started_at);

CREATE TABLE screentime_days (
    minor_id          uuid NOT NULL REFERENCES minors (id) ON DELETE CASCADE,
    day               date NOT NULL, -- the local date in the family zone
    seconds           integer NOT NULL DEFAULT 0,
    outside_seconds   integer NOT NULL DEFAULT 0,
    extension_minutes integer NOT NULL DEFAULT 0,
    PRIMARY KEY (minor_id, day)
);
CREATE INDEX screentime_days_day ON screentime_days (day);

CREATE TABLE screentime_extensions (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    minor_id   uuid NOT NULL REFERENCES minors (id) ON DELETE CASCADE,
    day        date NOT NULL,
    minutes    integer NOT NULL CHECK (minutes IN (15, 30, 60)),
    via        text NOT NULL CHECK (via IN ('pin', 'guardian')),
    account_id uuid REFERENCES accounts (id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL
);
CREATE INDEX screentime_extensions_day ON screentime_extensions (day);
