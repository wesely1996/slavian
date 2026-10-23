-- Push topics a player switched off (notifications.json `topics`).
ALTER TABLE accounts ADD COLUMN push_off text[] NOT NULL DEFAULT '{}';
