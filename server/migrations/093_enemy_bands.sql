-- The enemy's war bands in its lands (scheduler/enemyForces.ts): sallies
-- hunting a spotted army, and patrols marching between settlements.
CREATE TABLE enemy_bands (
  id             bigserial PRIMARY KEY,
  world_id       bigint NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
  front          text NOT NULL,
  kind           text NOT NULL CHECK (kind IN ('sally', 'patrol')),
  settlement_id  bigint REFERENCES enemy_settlements (id) ON DELETE SET NULL,
  units          jsonb NOT NULL,
  scouts         integer NOT NULL DEFAULT 0,
  status         text NOT NULL,
  path           jsonb NOT NULL,
  departs_at     timestamptz NOT NULL,
  arrives_at     timestamptz NOT NULL,
  target_army_id bigint
);
CREATE INDEX enemy_bands_world ON enemy_bands (world_id);

-- When a settlement may sally again.
ALTER TABLE enemy_settlements ADD COLUMN sally_ready_at timestamptz;
