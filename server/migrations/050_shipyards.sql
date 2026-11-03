-- Shipyards (data/events.json `shipyard`): a daily map event the group pays
-- for and defends while the boat is built; a finished one makes its river a
-- fast lane.
CREATE TABLE shipyards (
  id bigserial PRIMARY KEY,
  world_id bigint NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
  q integer NOT NULL,
  r integer NOT NULL,
  -- The river edge it is built on.
  aq integer NOT NULL,
  ar integer NOT NULL,
  bq integer NOT NULL,
  br integer NOT NULL,
  status text NOT NULL CHECK (status IN ('open', 'building', 'done')),
  cost jsonb NOT NULL,
  paid jsonb NOT NULL,
  front text NOT NULL,
  raiders jsonb NOT NULL,
  raids integer NOT NULL DEFAULT 0,
  ends_at timestamptz,
  completes_at timestamptz,
  next_raid_at timestamptz
);
CREATE INDEX shipyards_world ON shipyards (world_id);
