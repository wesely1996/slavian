-- Bug reports from players: their message plus the game state the app sent.
-- Kept for the developer; account_id is nullable so a report survives the
-- account's deletion.
CREATE TABLE reports (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  account_id bigint REFERENCES accounts (id) ON DELETE SET NULL,
  world_id   bigint REFERENCES worlds (id) ON DELETE SET NULL,
  message    text NOT NULL,
  state      jsonb NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX reports_created ON reports (created_at DESC);
