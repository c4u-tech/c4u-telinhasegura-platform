-- The pending invitations to one address, read when its account opens the
-- app with no family.
CREATE INDEX family_invitations_pending_email ON family_invitations (email)
    WHERE accepted_at IS NULL AND revoked_at IS NULL;
