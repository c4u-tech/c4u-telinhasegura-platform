-- Curation governance: every review answers a versioned list of
-- questions, a curator's doubt goes to a moderator, curators accept their
-- terms before reviewing, and moderators check a sample of approvals.

-- A review keeps the version of the list it answered and the answers: an
-- approval or a doubt keeps every answer (an object of question to
-- answer), a rejection the questions it failed (an array). Reviews written
-- before the list keep both empty. Erasing an old reviewer's account still
-- rewrites those rows, so the shape is checked only where a list exists.
ALTER TABLE video_reviews ADD COLUMN checklist_version text;
ALTER TABLE video_reviews ADD COLUMN checklist jsonb;
ALTER TABLE video_reviews DROP CONSTRAINT video_reviews_decision_check;
ALTER TABLE video_reviews ADD CONSTRAINT video_reviews_decision_check
    CHECK (decision IN ('approve', 'reject', 'doubt'));
ALTER TABLE video_reviews ADD CONSTRAINT video_reviews_checklist_pair
    CHECK ((checklist_version IS NULL) = (checklist IS NULL));
-- A doubt always carries its answers; a rejection lists at least one
-- question; an approval or a doubt answers them as an object.
ALTER TABLE video_reviews ADD CONSTRAINT video_reviews_checklist_shape CHECK (CASE
    WHEN checklist IS NULL THEN decision <> 'doubt'
    WHEN decision = 'reject' THEN jsonb_typeof(checklist) = 'array' AND checklist <> '[]'::jsonb
    ELSE jsonb_typeof(checklist) = 'object'
END);

-- A held video may wait for a moderator's answer to a doubt, or be held
-- because an audit disagreed with its approval.
ALTER TABLE videos DROP CONSTRAINT videos_held_reason_check;
ALTER TABLE videos ADD CONSTRAINT videos_held_reason_check
    CHECK (held_reason IN ('review', 'reports', 'unavailable', 'doubt', 'audit'));

-- Each acceptance of the curator terms, by version. No foreign key: it is
-- the proof of what a curator promised, so it outlives the role and the
-- account, keeping only the account's identifier.
CREATE TABLE curator_declarations (
    id          bigserial PRIMARY KEY,
    account_id  uuid NOT NULL,
    version     text NOT NULL,
    accepted_at timestamptz NOT NULL
);
CREATE UNIQUE INDEX curator_declarations_account_version ON curator_declarations (account_id, version);
CREATE INDEX curator_declarations_accepted ON curator_declarations (accepted_at);

-- A moderator's or an admin's check of one published round, once.
CREATE TABLE approval_audits (
    id         bigserial PRIMARY KEY,
    video_id   uuid NOT NULL REFERENCES videos (id) ON DELETE CASCADE,
    round      integer NOT NULL,
    auditor_id uuid REFERENCES accounts (id) ON DELETE SET NULL,
    verdict    text NOT NULL CHECK (verdict IN ('agree', 'disagree')),
    reason     text,
    audited_at timestamptz NOT NULL,
    UNIQUE (video_id, round),
    CHECK (verdict = 'agree' OR reason IS NOT NULL)
);
CREATE INDEX approval_audits_auditor ON approval_audits (auditor_id);

-- Every video in the catalogue is reviewed again under the list: its
-- revisit falls due now, and it stays visible to children until a review
-- refuses it.
UPDATE videos SET review_due_at = now() WHERE state = 'approved';
