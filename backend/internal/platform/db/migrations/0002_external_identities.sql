CREATE TABLE external_identities (
    provider   text NOT NULL CHECK (provider IN ('google', 'apple')),
    subject    text NOT NULL,
    account_id uuid NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL,
    PRIMARY KEY (provider, subject),
    UNIQUE (account_id, provider)
);

-- Digests of accepted provider ID tokens, kept until the token expires,
-- so each is accepted once.
CREATE TABLE used_provider_tokens (
    token_hash bytea PRIMARY KEY,
    expires_at timestamptz NOT NULL
);

CREATE TABLE provider_tickets (
    ticket_hash         bytea PRIMARY KEY,
    kind                text NOT NULL CHECK (kind IN ('signup', 'link')),
    provider            text NOT NULL CHECK (provider IN ('google', 'apple')),
    subject             text NOT NULL,
    email               text NOT NULL,
    email_authoritative boolean NOT NULL,
    account_id          uuid REFERENCES accounts (id) ON DELETE CASCADE,
    expires_at          timestamptz NOT NULL,
    used_at             timestamptz
);

-- Bumped by every credential change (password set, reset or cleared, email
-- changed). A check-then-write flow writes only if the version it checked
-- is still current, so nothing a squatter started before a clear_password
-- link lands after it.
ALTER TABLE accounts ADD COLUMN credential_version bigint NOT NULL DEFAULT 0;
