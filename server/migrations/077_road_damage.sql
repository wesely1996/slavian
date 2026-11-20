-- Roads damaged by fire (field.json road.damage): half as good until
-- repaired; 'repairing' while the work goes on.
ALTER TABLE road_edges ADD COLUMN damaged boolean NOT NULL DEFAULT false;
ALTER TABLE road_edges DROP CONSTRAINT road_edges_status_check;
ALTER TABLE road_edges ADD CONSTRAINT road_edges_status_check CHECK (status IN ('building', 'standing', 'upgrading', 'repairing'));
