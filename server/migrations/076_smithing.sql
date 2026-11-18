-- The Blacksmith (data/smithing.json): each player's forged levels
-- (unit -> line -> level) and the improvement being forged, if any.
ALTER TABLE world_members ADD COLUMN smithing jsonb NOT NULL DEFAULT '{}';
ALTER TABLE world_members ADD COLUMN smith_work jsonb;
