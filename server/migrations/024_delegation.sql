-- Delegation (M4 step 5): a player hands a teammate their villages for a while.
CREATE TABLE delegations (
  world_id            bigint NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
  owner_account_id    bigint NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
  delegate_account_id bigint NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
  since               timestamptz NOT NULL,
  until               timestamptz NOT NULL,
  PRIMARY KEY (world_id, owner_account_id)
);

-- What delegates did on their teammates' behalf.
CREATE TABLE delegation_log (
  id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  world_id            bigint NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
  owner_account_id    bigint NOT NULL,
  delegate_account_id bigint NOT NULL,
  village_id          bigint,
  action              text NOT NULL,
  at                  timestamptz NOT NULL
);
CREATE INDEX delegation_log_world ON delegation_log (world_id, at DESC);
