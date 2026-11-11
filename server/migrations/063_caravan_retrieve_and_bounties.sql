-- A caravan to one of its owner's settlements, forts or supply points can
-- bring resources back from there (taken on arrival, as far as there are).
ALTER TABLE caravans ADD COLUMN retrieve jsonb;

-- The Market's bounty board: a player offers resources (already paid,
-- with the fee) for others; anyone else in the group takes it at once.
CREATE TABLE bounties (
  id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  world_id         bigint NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
  village_id       bigint NOT NULL REFERENCES villages (id) ON DELETE CASCADE,
  owner_account_id bigint REFERENCES accounts (id) ON DELETE SET NULL,
  -- What the poster gives (paid when posting), what they want for it, and
  -- the fee they paid on top.
  offer            jsonb NOT NULL,
  want             jsonb NOT NULL,
  fee              jsonb NOT NULL,
  status           text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'taken', 'cancelled')),
  created_at       timestamptz NOT NULL,
  closed_at        timestamptz,
  taken_by_village_id bigint REFERENCES villages (id) ON DELETE SET NULL
);
CREATE INDEX bounties_open ON bounties (world_id) WHERE status = 'open';
