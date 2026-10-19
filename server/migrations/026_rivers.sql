-- Rivers (M5 step 3): edges between two neighbouring hexes (a, b) that
-- nothing crosses without a standing bridge (crossing). Players build more.
CREATE TABLE river_edges (
  world_id     bigint NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
  aq           integer NOT NULL,
  ar           integer NOT NULL,
  bq           integer NOT NULL,
  br           integer NOT NULL,
  crossing     text NOT NULL DEFAULT 'none' CHECK (crossing IN ('none', 'building', 'standing')),
  built_by     bigint REFERENCES villages (id) ON DELETE SET NULL,
  completes_at timestamptz,
  PRIMARY KEY (world_id, aq, ar, bq, br)
);
