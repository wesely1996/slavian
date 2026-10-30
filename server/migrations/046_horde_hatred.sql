-- Hatred: how much stronger a horde grows for being delayed by heroes'
-- ambushes and harassed by riders (data/horde.json `hatred`), a share added
-- to its attack and defense.
ALTER TABLE waves ADD COLUMN hatred double precision NOT NULL DEFAULT 0;
