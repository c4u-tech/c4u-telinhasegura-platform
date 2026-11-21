-- Review contract: an approval keeps the age band the server computed from
-- the answers and, when the curator chose another, why; a review keeps when
-- the curator began it; a curator's unfinished review is saved as a draft.

-- computed_band is the band the answers allow, set only on an approval.
-- band_reason explains a chosen band that differs from it, so it needs a
-- computed band to differ from. Reviews written before this keep all three
-- columns empty. began_at feeds the measures of how long a review takes,
-- hence the index on reviewed_at.
ALTER TABLE video_reviews ADD COLUMN computed_band text;
ALTER TABLE video_reviews ADD COLUMN band_reason text;
ALTER TABLE video_reviews ADD COLUMN began_at timestamptz;
ALTER TABLE video_reviews ADD CONSTRAINT video_reviews_computed_band
    CHECK (computed_band IN ('ate-4', '5-8', '9-12') AND decision = 'approve' OR computed_band IS NULL);
ALTER TABLE video_reviews ADD CONSTRAINT video_reviews_band_reason
    CHECK (band_reason IS NULL OR computed_band IS NOT NULL);
CREATE INDEX video_reviews_reviewed ON video_reviews (reviewed_at);

-- A draft hangs off the curator's role row, not the account: losing the
-- curator role, a suspension and an account erasure all remove it in one
-- rule. It is keyed by video and round, so a curator has one draft per
-- review under way. answers maps each answered question to its answer;
-- questions maps the same ids to the text as it was asked.
CREATE TABLE review_drafts (
    curator_id        uuid NOT NULL,
    role              text NOT NULL DEFAULT 'curator' CHECK (role = 'curator'),
    video_id          uuid NOT NULL REFERENCES videos (id) ON DELETE CASCADE,
    round             integer NOT NULL,
    checklist_version text NOT NULL,
    answers           jsonb NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(answers) = 'object'),
    questions         jsonb NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(questions) = 'object'),
    theme             text,
    min_age_band      text CHECK (min_age_band IN ('ate-4', '5-8', '9-12')),
    note              text,
    began_at          timestamptz NOT NULL,
    played_to_end_at  timestamptz,
    updated_at        timestamptz NOT NULL,
    PRIMARY KEY (curator_id, video_id, round),
    FOREIGN KEY (curator_id, role) REFERENCES platform_roles (account_id, role) ON DELETE CASCADE
);
CREATE INDEX review_drafts_video ON review_drafts (video_id);
