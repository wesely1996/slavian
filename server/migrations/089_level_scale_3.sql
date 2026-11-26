-- 0.24: the ten building levels give what the first ten did before 0.23
-- again (each was two of the old twenty). Villages saved on scale 1 or 2 get
-- their rates and stores counted again on server start (db/upgrades.ts
-- upgradeLevelScale); new ones are saved on scale 3.
ALTER TABLE villages ALTER COLUMN level_scale SET DEFAULT 3;
