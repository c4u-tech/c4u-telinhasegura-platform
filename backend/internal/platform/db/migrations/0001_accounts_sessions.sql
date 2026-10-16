CREATE TABLE accounts (
    id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    email                 text NOT NULL UNIQUE,
    password_hash         text,
    email_verified_at     timestamptz,
    adult_declared_at     timestamptz NOT NULL,
    failed_sign_ins       integer NOT NULL DEFAULT 0,
    sign_in_blocked_until timestamptz,
    created_at            timestamptz NOT NULL
);

CREATE TABLE email_tokens (
    token_hash bytea PRIMARY KEY,
    account_id uuid NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    purpose    text NOT NULL CHECK (purpose IN ('verify', 'change', 'reset')),
    new_email  text,
    expires_at timestamptz NOT NULL,
    used_at    timestamptz,
    created_at timestamptz NOT NULL
);
CREATE INDEX email_tokens_account_purpose ON email_tokens (account_id, purpose);

CREATE TABLE sessions (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id        uuid NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    client            text NOT NULL CHECK (client IN ('web', 'mobile')),
    device_label      text NOT NULL DEFAULT '',
    secret_hash       bytea NOT NULL UNIQUE,
    access_expires_at timestamptz,
    refresh_hash      bytea UNIQUE,
    csrf_token        text,
    reauth_at         timestamptz,
    created_at        timestamptz NOT NULL,
    last_seen_at      timestamptz NOT NULL,
    revoked_at        timestamptz
);
CREATE INDEX sessions_account ON sessions (account_id);

CREATE TABLE used_refresh_tokens (
    refresh_hash bytea PRIMARY KEY,
    session_id   uuid NOT NULL REFERENCES sessions (id) ON DELETE CASCADE
);

CREATE TABLE audit_events (
    id          bigserial PRIMARY KEY,
    account_id  uuid,
    event       text NOT NULL,
    occurred_at timestamptz NOT NULL
);
