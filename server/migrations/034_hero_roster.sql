-- Hero roster (M5 step 21): the hero each member picked (data/heroes.json
-- roster); null until they pick, filled in for everyone when the run starts.
ALTER TABLE world_members ADD COLUMN hero_kind text;
