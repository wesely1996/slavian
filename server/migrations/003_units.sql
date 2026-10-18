ALTER TABLE villages
  -- Units at home, by unit id.
  ADD COLUMN garrison jsonb NOT NULL DEFAULT '{}',
  -- Training batches, trained one unit after another (see sim/training.ts).
  ADD COLUMN training jsonb NOT NULL DEFAULT '[]';
