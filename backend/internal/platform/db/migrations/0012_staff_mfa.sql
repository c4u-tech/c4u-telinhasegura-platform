-- Admin area: privileged MFA.

-- A session's privileged elevation, NULL until a challenge.
-- session owns the column; staff writes it through session.MarkElevated
-- and session.ClearElevation inside its own transactions.
ALTER TABLE sessions ADD COLUMN elevated_until timestamptz;

-- One TOTP factor per account; confirmed_at NULL is a
-- pending enrollment. secret_sealed is AES-GCM under STAFF_MFA_KEY with
-- the account id as associated data. last_step stops a
-- replay. failed_attempts and blocked_until are the lockout,
-- shared by TOTP and recovery codes.
CREATE TABLE staff_mfa (
    account_id      uuid PRIMARY KEY REFERENCES accounts (id) ON DELETE CASCADE,
    secret_sealed   bytea NOT NULL,
    confirmed_at    timestamptz,
    last_step       bigint,
    failed_attempts int NOT NULL DEFAULT 0,
    blocked_until   timestamptz,
    created_at      timestamptz NOT NULL
);

-- Ten single-use recovery codes per confirmed factor, as SHA-256
-- digests of their normalized form.
CREATE TABLE staff_recovery_codes (
    account_id uuid NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    code_hash  bytea NOT NULL,
    used_at    timestamptz,
    created_at timestamptz NOT NULL,
    PRIMARY KEY (account_id, code_hash)
);
