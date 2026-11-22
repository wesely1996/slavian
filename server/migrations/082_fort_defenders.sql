-- The Fort Garrison's defenders (forts.json garrison): units in the fort,
-- who never leave it.
ALTER TABLE forts ADD COLUMN defenders jsonb NOT NULL DEFAULT '{}'::jsonb;
