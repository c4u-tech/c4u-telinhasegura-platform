-- Consent history: a child's profile may be authorized again when the
-- consent text changes, and every authorization stays as proof. Accounts
-- record which version of the terms and privacy policy they accepted.
ALTER TABLE minor_consents DROP CONSTRAINT minor_consents_pkey;
ALTER TABLE minor_consents ADD COLUMN id bigserial PRIMARY KEY;
CREATE INDEX minor_consents_minor ON minor_consents (minor_id, granted_at DESC);

ALTER TABLE accounts
    ADD COLUMN terms_version text,
    ADD COLUMN terms_accepted_at timestamptz,
    ADD CONSTRAINT accounts_terms_pair CHECK ((terms_version IS NULL) = (terms_accepted_at IS NULL));
