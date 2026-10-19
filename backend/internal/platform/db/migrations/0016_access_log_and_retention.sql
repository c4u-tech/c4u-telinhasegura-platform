-- The access record: when, and from which address and port, each account
-- and each linked device used the service. Brazilian law requires an
-- application provider to keep it for six months, so a row has no foreign
-- key: it outlives the account, the session and the device it names until
-- the retention sweep deletes it.
CREATE TABLE access_log (
    id          bigserial PRIMARY KEY,
    account_id  uuid,
    device_id   uuid,
    session_id  uuid,
    ip          inet NOT NULL,
    port        integer CHECK (port BETWEEN 1 AND 65535),
    occurred_at timestamptz NOT NULL DEFAULT now(),
    CHECK (account_id IS NOT NULL OR device_id IS NOT NULL)
);
CREATE INDEX access_log_occurred ON access_log (occurred_at);
CREATE INDEX access_log_account ON access_log (account_id, occurred_at);
-- One row per session (else device, else account) and address per hour:
-- the recording looks for a recent row by these columns.
CREATE INDEX access_log_recent ON access_log ((coalesce(session_id, device_id, account_id)), ip, occurred_at);

-- The retention sweeps delete by these columns.
CREATE INDEX minor_consents_withdrawn ON minor_consents (withdrawn_at) WHERE withdrawn_at IS NOT NULL;
CREATE INDEX audit_events_occurred ON audit_events (occurred_at);
