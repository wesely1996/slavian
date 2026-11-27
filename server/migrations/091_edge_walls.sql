-- Walls along hex edges (data/field.json edgeWalls): one row an edge, a
-- before b (sim/land.ts edgeKey order). `kind` 'wall' or 'gate' (a
-- gatehouse), `tier` from 1 (0 while the first is being built); 'upgrading':
-- standing at `tier` while raised to the next.
CREATE TABLE edge_walls (
  world_id bigint NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
  aq integer NOT NULL,
  ar integer NOT NULL,
  bq integer NOT NULL,
  br integer NOT NULL,
  kind text NOT NULL,
  tier integer NOT NULL DEFAULT 0,
  status text NOT NULL,
  built_by bigint REFERENCES villages (id) ON DELETE SET NULL,
  owner_account_id bigint REFERENCES accounts (id) ON DELETE SET NULL,
  completes_at timestamptz,
  PRIMARY KEY (world_id, aq, ar, bq, br)
);
