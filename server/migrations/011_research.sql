-- The owner's research effects, carried by each of their villages.
ALTER TABLE villages ADD COLUMN bonuses jsonb NOT NULL DEFAULT '{}';

-- Per-player research in a world. One tech at a time per player.
CREATE TABLE research (
  world_id     bigint NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
  account_id   bigint NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
  tech         text NOT NULL,
  status       text NOT NULL CHECK (status IN ('researching', 'done')),
  -- The village whose Academy studies it (and paid for it).
  village_id   bigint REFERENCES villages (id) ON DELETE SET NULL,
  started_at   timestamptz NOT NULL,
  completes_at timestamptz NOT NULL,
  PRIMARY KEY (world_id, account_id, tech)
);
CREATE UNIQUE INDEX research_one_at_a_time ON research (world_id, account_id) WHERE status = 'researching';
