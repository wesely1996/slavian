-- Daily pruning (scheduler/prune.ts): what was deleted still counts in the
-- run's summary.
ALTER TABLE worlds ADD COLUMN pruned jsonb NOT NULL DEFAULT '{}';
