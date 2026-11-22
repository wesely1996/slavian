-- Forts as strongholds (forts.json): their buildings (plots: the Keep, the
-- Storage, the wall rings and their towers) and the one rising; a fort, a
-- supply point and an outpost may share a hex; a player's rally point may
-- be one of their forts.
ALTER TABLE forts ADD COLUMN plots jsonb NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE forts ADD COLUMN work jsonb;
UPDATE forts SET plots = '{"keep": {"kind": "keep", "level": 1}, "storage": {"kind": "storage", "level": 1}}'::jsonb WHERE kind = 'fort';
ALTER TABLE forts DROP CONSTRAINT forts_world_id_q_r_key;
ALTER TABLE forts ADD CONSTRAINT forts_world_id_q_r_kind_key UNIQUE (world_id, q, r, kind);
ALTER TABLE world_members ADD COLUMN rally_fort_id bigint REFERENCES forts (id) ON DELETE SET NULL;
