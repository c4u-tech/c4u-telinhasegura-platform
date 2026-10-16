-- Transactional email.

-- A message waits here until the worker delivers it. A sent message is
-- deleted; one that ends unsent (failed, expired, suppressed) loses its
-- body, which may hold the only plaintext token, and is deleted 7 days
-- after ended_at. Erasure deletes the rows addressed to the account.
-- Additive only.
CREATE TABLE mail_outbox (
    id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    to_address      text        NOT NULL,
    subject         text        NOT NULL,
    body            text,
    status          text        NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending', 'failed', 'expired', 'suppressed')),
    attempts        int         NOT NULL DEFAULT 0,
    next_attempt_at timestamptz NOT NULL,
    expires_at      timestamptz NOT NULL,
    last_error      text,
    created_at      timestamptz NOT NULL,
    ended_at        timestamptz
);
CREATE INDEX mail_outbox_due ON mail_outbox (next_attempt_at) WHERE status = 'pending';
CREATE INDEX mail_outbox_ended ON mail_outbox (ended_at) WHERE status <> 'pending';
CREATE INDEX mail_outbox_to ON mail_outbox (to_address);
