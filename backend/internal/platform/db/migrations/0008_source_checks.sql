-- When a video's stored YouTube data was last re-checked with
-- videos.list (Developer Policies III.E.4).
ALTER TABLE videos ADD COLUMN source_checked_at timestamptz;
CREATE INDEX videos_source_checked ON videos (source_checked_at NULLS FIRST);
