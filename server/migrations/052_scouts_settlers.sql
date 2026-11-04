-- Scout missions carry scouts of every kind (data/units.json `scouting`):
-- what was sent and what came through. Players count the units they bought
-- that grow dearer (settlers: units.json `costStep`).
ALTER TABLE scout_missions ADD COLUMN units jsonb;
ALTER TABLE scout_missions ADD COLUMN survivor_units jsonb;
ALTER TABLE world_members ADD COLUMN bought jsonb NOT NULL DEFAULT '{}';
