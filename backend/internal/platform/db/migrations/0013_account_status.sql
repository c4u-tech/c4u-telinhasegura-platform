-- Admin area: suspension.

-- identity owns the columns. staff writes them only through
-- identity.MarkSuspended and identity.MarkActive, inside its own
-- transaction. The reason is a staff note: it never reaches
-- the person, and erasure deletes it with the row.
-- The fields hold together: both set exactly while suspended.
ALTER TABLE accounts
    ADD COLUMN status            text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended')),
    ADD COLUMN suspended_at      timestamptz,
    ADD COLUMN suspension_reason text,
    ADD CONSTRAINT accounts_suspension_fields CHECK (
        ((status = 'suspended') = (suspended_at IS NOT NULL))
        AND ((status = 'suspended') = (suspension_reason IS NOT NULL)));
