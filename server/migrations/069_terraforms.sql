-- Land being reshaped near a village (field.json terraform): a forest
-- cleared, trees planted, a swamp drained. One work to a hex; when it is
-- done the hex's terrain changes and the row goes.
CREATE TABLE terraforms (
  world_id     bigint NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
  q            integer NOT NULL,
  r            integer NOT NULL,
  action       text NOT NULL,
  village_id   bigint REFERENCES villages (id) ON DELETE SET NULL,
  completes_at timestamptz NOT NULL,
  -- A burning forest: 0 where it was set alight, then one more for each
  -- hex the fire spread to from there.
  generation   integer NOT NULL DEFAULT 0,
  PRIMARY KEY (world_id, q, r)
);
