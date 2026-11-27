-- The enemy's settlements in its lands (data/enemy-lands.json settlements;
-- scheduler/enemySettlements.ts): founded the deepest band first, each
-- building its walls, road and moat in turn.
CREATE TABLE enemy_settlements (
  id         bigserial PRIMARY KEY,
  world_id   bigint NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
  front      text NOT NULL,
  kind       text NOT NULL,
  band       integer NOT NULL,
  q          integer NOT NULL,
  r          integer NOT NULL,
  status     text NOT NULL DEFAULT 'standing',
  -- The garrison (unit -> count) and its scouts: filled by the enemy's forces.
  garrison   jsonb NOT NULL DEFAULT '{}'::jsonb,
  founded_at timestamptz NOT NULL
);
CREATE INDEX enemy_settlements_world ON enemy_settlements (world_id);

-- Walls the enemy raised in its lands: the front's (null for the players').
ALTER TABLE edge_walls ADD COLUMN front text;
