-- Admin area: staff.

-- platform_roles is owned by staff from here on. A moderator,
-- like an admin, has no displayed role: platform_roles_check still ties
-- display_role to the curator role alone.
ALTER TABLE platform_roles DROP CONSTRAINT platform_roles_role_check;
ALTER TABLE platform_roles ADD CONSTRAINT platform_roles_role_check
    CHECK (role IN ('admin', 'curator', 'moderator'));

-- Audit actions: a staff write names its actor's role, a typed subject
-- and why. Every new column is NULL on the events Record writes.
-- metadata holds ids and enum values only.
-- Erasure keeps the ids and clears the reasons about the erased
-- account, which the index serves.
ALTER TABLE audit_events
    ADD COLUMN actor_role   text CHECK (actor_role IN ('admin', 'curator', 'moderator')),
    ADD COLUMN subject_kind text CHECK (subject_kind IN ('account', 'video', 'pack')),
    ADD COLUMN subject_id   uuid,
    ADD COLUMN reason       text,
    ADD COLUMN metadata     jsonb,
    ADD CONSTRAINT audit_events_subject_pair CHECK ((subject_kind IS NULL) = (subject_id IS NULL));
CREATE INDEX audit_events_subject ON audit_events (subject_kind, subject_id);
