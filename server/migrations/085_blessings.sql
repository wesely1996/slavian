-- The gods' blessings (events.json blessings): when each came, and the
-- longest river line the players have dug so far.
ALTER TABLE worlds ADD COLUMN blessings jsonb NOT NULL DEFAULT '{}'::jsonb;
-- Rivers the players dug (field.json terraform river), apart from the map's own.
ALTER TABLE river_edges ADD COLUMN dug boolean NOT NULL DEFAULT false;
