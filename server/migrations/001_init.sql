CREATE TABLE worlds (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name       text NOT NULL,
  seed       bigint NOT NULL,
  -- World speed multiplies production and divides durations (1 = real time).
  speed      double precision NOT NULL DEFAULT 1 CHECK (speed > 0),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE villages (
  id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  world_id       bigint NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
  q              integer NOT NULL,
  r              integer NOT NULL,
  name           text NOT NULL,
  levels         jsonb NOT NULL DEFAULT '{}',
  -- Lazy resource ledger: current amount = amounts + rates * (now - settled_at), capped.
  amounts        jsonb NOT NULL,
  rates_per_hour jsonb NOT NULL,
  capacity       jsonb NOT NULL,
  settled_at     timestamptz NOT NULL,
  queue          jsonb NOT NULL DEFAULT '[]',
  UNIQUE (world_id, q, r)
);

-- Every timed thing in the game is a row here. A world's events are only
-- processed by whoever holds that world's advisory lock.
CREATE TABLE scheduled_events (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  world_id     bigint NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
  due_at       timestamptz NOT NULL,
  type         text NOT NULL,
  payload      jsonb NOT NULL DEFAULT '{}',
  status       text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'done', 'failed')),
  processed_at timestamptz,
  error        text,
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX scheduled_events_world_pending ON scheduled_events (world_id, due_at, id) WHERE status = 'pending';
CREATE INDEX scheduled_events_pending_due ON scheduled_events (due_at) WHERE status = 'pending';
