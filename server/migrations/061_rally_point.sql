-- A player's rally point: one of their own villages, where every batch of
-- troops trained in their other villages marches as soon as it is done
-- (null: none).
ALTER TABLE world_members ADD COLUMN rally_village_id bigint REFERENCES villages (id) ON DELETE SET NULL;
