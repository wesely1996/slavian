-- Enemy heroes (M5 step 8): every front has one named leader at a time, who
-- leads its hordes, grows from what they win, and dies or comes back.
CREATE TABLE enemy_leaders (
  id                bigserial PRIMARY KEY,
  world_id          bigint NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
  front             text NOT NULL,
  name              text NOT NULL,
  level             integer NOT NULL DEFAULT 1,
  xp                integer NOT NULL DEFAULT 0,
  skills            jsonb NOT NULL DEFAULT '{}',
  -- A wounded leader is alive with wounded_until ahead.
  status            text NOT NULL DEFAULT 'alive' CHECK (status IN ('alive', 'dead')),
  wounded_until     timestamptz,
  battles           integer NOT NULL DEFAULT 0,
  wins              integer NOT NULL DEFAULT 0,
  losses            integer NOT NULL DEFAULT 0,
  razed             integer NOT NULL DEFAULT 0,
  kills             integer NOT NULL DEFAULT 0,
  -- The village that last beat them: they strike it harder.
  grudge_village_id bigint REFERENCES villages (id) ON DELETE SET NULL,
  created_at        timestamptz NOT NULL DEFAULT now(),
  died_at           timestamptz
);
CREATE UNIQUE INDEX enemy_leaders_one_alive ON enemy_leaders (world_id, front) WHERE status = 'alive';

ALTER TABLE waves ADD COLUMN leader_id bigint REFERENCES enemy_leaders (id) ON DELETE SET NULL;
