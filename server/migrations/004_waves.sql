-- Enemy waves. Front, timing and threat level are public; composition is
-- only revealed by scouting (M1 step 4).
CREATE TABLE waves (
  id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  world_id          bigint NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
  index             integer NOT NULL,
  front             text NOT NULL,
  status            text NOT NULL DEFAULT 'scheduled'
                    CHECK (status IN ('scheduled', 'marching', 'arrived', 'dispersed')),
  threat            text NOT NULL,
  composition       jsonb NOT NULL,
  spawn_at          timestamptz NOT NULL,
  -- Set when the wave spawns:
  spawn_q           integer,
  spawn_r           integer,
  target_village_id bigint REFERENCES villages (id) ON DELETE SET NULL,
  path              jsonb,
  arrives_at        timestamptz,
  ends_at           timestamptz,
  UNIQUE (world_id, index)
);
