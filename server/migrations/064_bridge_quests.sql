-- The bridge's quests raise places of their own (a ruin, a lair) and a host
-- of their own (a quest army), and while a stage is raised each front sends
-- a small horde at the bridge's builders: what quest a ruin or lair answers,
-- and what errand a horde is on ({kind: 'bridge' | 'quest', target: a
-- village id, or null for the Holy City}).
ALTER TABLE sites ADD COLUMN quest text;
ALTER TABLE camps ADD COLUMN quest text;
ALTER TABLE waves ADD COLUMN errand jsonb;

-- How many times raiders have burned a shipyard's work (data/events.json
-- shipyard.maxBurns: that many, and the boatwrights give up).
ALTER TABLE shipyards ADD COLUMN burns integer NOT NULL DEFAULT 0;
