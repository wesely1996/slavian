-- Mountain cities (data/events.json `mountain_city`): built and defended like
-- a shipyard, so they share its table; `kind` tells them apart. A mountain
-- city has no river edge: its edge columns repeat its own hex.
ALTER TABLE shipyards ADD COLUMN kind text NOT NULL DEFAULT 'boat' CHECK (kind IN ('boat', 'mountain_city'));
