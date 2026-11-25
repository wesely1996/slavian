-- Scouts searching for ruins (scouting.json ruinSearch) know where they will
-- find one, or that they won't, from when they set out: how long they are
-- away depends on it. The ruin is placed when they are back.
ALTER TABLE ruin_searches ADD COLUMN plan jsonb;
