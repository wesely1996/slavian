-- A band a hating horde sent out (data/horde.json hatred.bandShare): a
-- small horde of its own, raiding the nearest village.
ALTER TABLE waves ADD COLUMN band_of bigint REFERENCES waves (id) ON DELETE SET NULL;

-- A band keeps its horde's wave index: only hordes are one per index.
ALTER TABLE waves DROP CONSTRAINT waves_world_id_index_key;
CREATE UNIQUE INDEX waves_world_index ON waves (world_id, index) WHERE band_of IS NULL;
