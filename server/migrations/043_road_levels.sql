-- Roads have levels (data/field.json `road.levels`), each cheaper to travel
-- than the last. A road being improved ('upgrading') keeps its level until
-- the work is done. Roads built before are level 1, as fast as they were.
ALTER TABLE road_edges ADD COLUMN level integer NOT NULL DEFAULT 1;
ALTER TABLE road_edges DROP CONSTRAINT road_edges_status_check;
ALTER TABLE road_edges ADD CONSTRAINT road_edges_status_check CHECK (status IN ('building', 'standing', 'upgrading'));
