-- Ritual Night and the end of a run (M4 step 3).
ALTER TABLE waves ADD COLUMN ritual boolean NOT NULL DEFAULT false;
ALTER TABLE worlds ADD COLUMN ritual_at timestamptz;
ALTER TABLE worlds ADD COLUMN ended_at timestamptz;
