-- Units away from home (scouts on a mission). They still eat.
ALTER TABLE villages ADD COLUMN away jsonb NOT NULL DEFAULT '{}';

CREATE TABLE scout_missions (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  world_id   bigint NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
  village_id bigint NOT NULL REFERENCES villages (id) ON DELETE CASCADE,
  wave_id    bigint NOT NULL REFERENCES waves (id) ON DELETE CASCADE,
  sent       integer NOT NULL CHECK (sent > 0),
  survivors  integer,
  status     text NOT NULL DEFAULT 'outbound' CHECK (status IN ('outbound', 'returning', 'done')),
  target_q   integer NOT NULL,
  target_r   integer NOT NULL,
  departs_at timestamptz NOT NULL,
  arrives_at timestamptz NOT NULL,
  returns_at timestamptz NOT NULL,
  -- Filled in when the scouts reach the wave; shared with the whole group.
  report     jsonb
);
CREATE INDEX scout_missions_world ON scout_missions (world_id);
