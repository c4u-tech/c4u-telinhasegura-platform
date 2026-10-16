CREATE TABLE families (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at timestamptz NOT NULL
);

-- One family per account (UNIQUE account_id) and one owner per family
-- (the partial index).
CREATE TABLE family_members (
    family_id  uuid NOT NULL REFERENCES families (id) ON DELETE CASCADE,
    account_id uuid NOT NULL UNIQUE REFERENCES accounts (id) ON DELETE CASCADE,
    role       text NOT NULL CHECK (role IN ('owner', 'guardian')),
    joined_at  timestamptz NOT NULL,
    PRIMARY KEY (family_id, account_id)
);
CREATE UNIQUE INDEX family_members_one_owner ON family_members (family_id) WHERE role = 'owner';

CREATE TABLE family_invitations (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    token_hash  bytea NOT NULL UNIQUE,
    family_id   uuid NOT NULL REFERENCES families (id) ON DELETE CASCADE,
    email       text NOT NULL,
    invited_by  uuid NOT NULL,
    created_at  timestamptz NOT NULL,
    expires_at  timestamptz NOT NULL,
    accepted_at timestamptz,
    revoked_at  timestamptz
);
CREATE INDEX family_invitations_family ON family_invitations (family_id);

CREATE TABLE minors (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    family_id  uuid NOT NULL REFERENCES families (id) ON DELETE CASCADE,
    nickname   text NOT NULL,
    avatar     text NOT NULL,
    age_band   text NOT NULL CHECK (age_band IN ('ate-4', '5-8', '9-12')),
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL
);
CREATE INDEX minors_family ON minors (family_id);

-- The consent ledger outlives the minor, the family and the guardian's
-- account (LGPD art. 16 II): no foreign keys and no child data.
CREATE TABLE minor_consents (
    minor_id       uuid PRIMARY KEY,
    family_id      uuid NOT NULL,
    granted_by     uuid NOT NULL,
    policy_version text NOT NULL,
    granted_at     timestamptz NOT NULL,
    withdrawn_at   timestamptz,
    withdrawn_by   uuid
);
CREATE INDEX minor_consents_family ON minor_consents (family_id);
