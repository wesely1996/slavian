-- The military reserve: grain kept for armies in the military buildings
-- (data/armies.json `reserve`), apart from the granary.
ALTER TABLE villages ADD COLUMN reserve double precision NOT NULL DEFAULT 0;

-- A wagon fort: when the army's wagons stand ready in a ring (null: none).
ALTER TABLE armies ADD COLUMN wagon_fort_at timestamptz;
