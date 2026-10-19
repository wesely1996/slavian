-- Camps and lairs (M3 step 5): armies clear them, caravans get ambushed by
-- them, abandoned forts turn into them; lairs may hold Svarog's Ember.
ALTER TABLE battles
  ALTER COLUMN wave_id DROP NOT NULL,
  -- An army storming a camp (no wave).
  ADD COLUMN camp_id bigint REFERENCES camps (id) ON DELETE SET NULL;
ALTER TABLE battles DROP CONSTRAINT battles_status_check;
ALTER TABLE battles ADD CONSTRAINT battles_status_check
  CHECK (status IN ('ongoing', 'defended', 'raided', 'cleared', 'repelled'));

ALTER TABLE armies DROP CONSTRAINT armies_orders_check;
ALTER TABLE armies ADD CONSTRAINT armies_orders_check CHECK (orders IN ('support', 'reinforce', 'harass', 'hold', 'clear'));
-- What an army carries home from a camp it cleared.
ALTER TABLE armies ADD COLUMN loot jsonb;

-- Troops guarding a caravan, and what happened if it was ambushed.
ALTER TABLE caravans
  ADD COLUMN escort jsonb NOT NULL DEFAULT '{}',
  ADD COLUMN ambush jsonb;

-- The last time an army held the fort; left alone too long, it falls to bandits.
ALTER TABLE forts ADD COLUMN manned_at timestamptz;

-- The group's Svarog's Ember.
ALTER TABLE worlds ADD COLUMN embers integer NOT NULL DEFAULT 0;
