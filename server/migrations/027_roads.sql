-- Roads (M5 step 4): edges between two neighbouring hexes (a, b) that are
-- cheaper to travel, for everyone but the Monsters of the North.
CREATE TABLE road_edges (
  world_id     bigint NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
  aq           integer NOT NULL,
  ar           integer NOT NULL,
  bq           integer NOT NULL,
  br           integer NOT NULL,
  status       text NOT NULL DEFAULT 'building' CHECK (status IN ('building', 'standing')),
  built_by     bigint REFERENCES villages (id) ON DELETE SET NULL,
  completes_at timestamptz,
  PRIMARY KEY (world_id, aq, ar, bq, br)
);
