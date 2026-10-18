-- One hero per player per world.
CREATE TABLE heroes (
  world_id       bigint NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
  account_id     bigint NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
  name           text NOT NULL,
  status         text NOT NULL DEFAULT 'home' CHECK (status IN ('home', 'traveling', 'wounded')),
  -- Where it stands (home or wounded), or where it is heading.
  village_id     bigint REFERENCES villages (id) ON DELETE SET NULL,
  level          integer NOT NULL DEFAULT 1,
  xp             integer NOT NULL DEFAULT 0,
  skill_points   integer NOT NULL DEFAULT 0,
  skills         jsonb NOT NULL DEFAULT '{}',
  gear           jsonb NOT NULL DEFAULT '{}',
  inventory      jsonb NOT NULL DEFAULT '[]',
  -- Travelling: the road (like caravans) and when it arrives.
  path           jsonb,
  departs_at     timestamptz,
  arrives_at     timestamptz,
  wounded_until  timestamptz,
  PRIMARY KEY (world_id, account_id)
);
