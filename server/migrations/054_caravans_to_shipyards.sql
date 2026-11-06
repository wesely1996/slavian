-- A caravan can carry resources to a shipyard (a daily event's boat).
-- No foreign key: a shipyard that goes is told by its absence, and the
-- caravan brings its load home.
ALTER TABLE caravans ADD COLUMN destination_shipyard_id bigint;
