-- Armies and garrisons eat from the granary again: the military reserve's
-- grain goes back into it (as far as it holds it), and the reserve is gone.
UPDATE villages
SET amounts = jsonb_set(amounts, '{grain}', to_jsonb(LEAST((amounts->>'grain')::float8 + reserve, (capacity->>'grain')::float8)))
WHERE reserve IS NOT NULL AND reserve > 0;
ALTER TABLE villages DROP COLUMN reserve;

-- Garrisons no longer march to battles nearby (armies answer them).
ALTER TABLE villages DROP COLUMN reinforce_share, DROP COLUMN reinforce_range;

-- How low a settlement's, fort's or supply point's grain may fall for
-- armies quartered there or filling up (null: the default, data/armies.json).
ALTER TABLE villages ADD COLUMN army_floor double precision;
ALTER TABLE forts ADD COLUMN army_floor double precision;

-- An army quartered in a settlement, fort or supply point: fed by it since
-- quartered_at (null: it eats its own grain). Whether it answers battles
-- nearby, and where it stood when it went to one (it goes back after).
ALTER TABLE armies ADD COLUMN quartered_at timestamptz;
ALTER TABLE armies ADD COLUMN respond boolean NOT NULL DEFAULT true;
ALTER TABLE armies ADD COLUMN post jsonb;
