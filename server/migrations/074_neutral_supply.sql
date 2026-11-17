-- A neutral supply point (a built mountain city's, events.json mountain_city):
-- nobody's, any army can draw on it and any caravan fill it, and no horde
-- burns it or bandit takes it.
ALTER TABLE forts ADD COLUMN neutral boolean NOT NULL DEFAULT false;
