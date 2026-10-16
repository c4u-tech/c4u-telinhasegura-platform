-- Parental controls: the family PIN, link codes, linked devices and kid-mode
-- locks. Every row hangs off its family or minor with a cascade, so
-- deleting either revokes what it held.

CREATE TABLE family_pins (
    family_id       uuid PRIMARY KEY REFERENCES families (id) ON DELETE CASCADE,
    pin_hash        text NOT NULL,
    failed_attempts integer NOT NULL DEFAULT 0,
    blocked_until   timestamptz,
    updated_at      timestamptz NOT NULL
);

CREATE TABLE link_codes (
    code_hash  bytea PRIMARY KEY,
    family_id  uuid NOT NULL REFERENCES families (id) ON DELETE CASCADE,
    minor_id   uuid NOT NULL REFERENCES minors (id) ON DELETE CASCADE,
    created_by uuid NOT NULL,
    expires_at timestamptz NOT NULL,
    used_at    timestamptz
);
CREATE INDEX link_codes_family ON link_codes (family_id);
CREATE INDEX link_codes_minor ON link_codes (minor_id);

CREATE TABLE devices (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    family_id    uuid NOT NULL REFERENCES families (id) ON DELETE CASCADE,
    minor_id     uuid NOT NULL REFERENCES minors (id) ON DELETE CASCADE,
    token_hash   bytea NOT NULL UNIQUE,
    label        text NOT NULL,
    linked_at    timestamptz NOT NULL,
    last_seen_at timestamptz NOT NULL
);
CREATE INDEX devices_family ON devices (family_id);
CREATE INDEX devices_minor ON devices (minor_id);

-- SET NULL, not CASCADE: a session locked to a deleted child stays locked
-- with no profile, never falling back into the guardian area.
CREATE TABLE session_kid_locks (
    session_id uuid PRIMARY KEY REFERENCES sessions (id) ON DELETE CASCADE,
    minor_id   uuid REFERENCES minors (id) ON DELETE SET NULL,
    locked_at  timestamptz NOT NULL
);
CREATE INDEX session_kid_locks_minor ON session_kid_locks (minor_id);
