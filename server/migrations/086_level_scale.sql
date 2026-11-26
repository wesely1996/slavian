-- Buildings that rose to level 20 now rise to 10, each level two of the old
-- (0.23). Villages saved before then hold old levels (1) until the server's
-- upgrade on start halves them (db/upgrades.ts upgradeLevelScale); new ones
-- are laid out on the new scale (2).
ALTER TABLE villages ADD COLUMN level_scale smallint NOT NULL DEFAULT 1;
ALTER TABLE villages ALTER COLUMN level_scale SET DEFAULT 2;
