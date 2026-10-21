-- Quitting a world: a player who leaves a running world stays on its record
-- (run summaries, logs) but is no longer one of its players. A world whose
-- last player leaves is abandoned: it stands still, like a finished run, and
-- doesn't count as a loss.
ALTER TABLE world_members ADD COLUMN left_at timestamptz;

ALTER TABLE worlds DROP CONSTRAINT IF EXISTS worlds_status_check;
ALTER TABLE worlds ADD CONSTRAINT worlds_status_check
  CHECK (status IN ('lobby', 'running', 'won', 'lost', 'abandoned'));
