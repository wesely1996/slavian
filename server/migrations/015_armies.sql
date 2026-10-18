-- How a village answers battles nearby: send this share of its troops to
-- any battle within this many hexes (0: never).
ALTER TABLE villages
  ADD COLUMN reinforce_share real NOT NULL DEFAULT 0.5,
  ADD COLUMN reinforce_range integer NOT NULL DEFAULT 4;

-- Troops out of their village.
CREATE TABLE armies (
  id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  world_id          bigint NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
  owner_account_id  bigint REFERENCES accounts (id) ON DELETE SET NULL,
  home_village_id   bigint NOT NULL REFERENCES villages (id) ON DELETE CASCADE,
  target_village_id bigint NOT NULL REFERENCES villages (id) ON DELETE CASCADE,
  orders            text NOT NULL CHECK (orders IN ('support', 'reinforce', 'harass')),
  units             jsonb NOT NULL,
  status            text NOT NULL DEFAULT 'marching'
                    CHECK (status IN ('marching', 'stationed', 'engaged', 'returning', 'done')),
  battle_id         bigint REFERENCES battles (id) ON DELETE SET NULL,
  -- The round it fights first in, and its bonus that round.
  joins_round       integer,
  join_bonus        real NOT NULL DEFAULT 0,
  path              jsonb NOT NULL,
  departs_at        timestamptz NOT NULL,
  arrives_at        timestamptz NOT NULL,
  -- Heading home: when it set out back, and when it gets there.
  leaves_at         timestamptz,
  returns_at        timestamptz
);
CREATE INDEX armies_world ON armies (world_id, status);
CREATE INDEX armies_target ON armies (target_village_id) WHERE status IN ('stationed', 'engaged');
