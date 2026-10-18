ALTER TABLE waves ADD COLUMN stance text NOT NULL DEFAULT 'balanced';
ALTER TABLE waves DROP CONSTRAINT waves_status_check;
ALTER TABLE waves ADD CONSTRAINT waves_status_check
  CHECK (status IN ('scheduled', 'marching', 'arrived', 'battling', 'defeated', 'dispersed'));

-- The stance a village's garrison fights with.
ALTER TABLE villages ADD COLUMN stance text NOT NULL DEFAULT 'balanced';

CREATE TABLE battles (
  id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  world_id         bigint NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
  wave_id          bigint NOT NULL REFERENCES waves (id) ON DELETE CASCADE,
  village_id       bigint NOT NULL REFERENCES villages (id) ON DELETE CASCADE,
  status           text NOT NULL DEFAULT 'ongoing' CHECK (status IN ('ongoing', 'defended', 'raided')),
  round            integer NOT NULL DEFAULT 0,
  attacker_stance  text NOT NULL,
  -- Units at the start of the battle; current numbers live on the wave and
  -- the village garrison.
  attacker_initial jsonb NOT NULL,
  defender_initial jsonb NOT NULL,
  rounds           jsonb NOT NULL DEFAULT '[]',
  loot             jsonb,
  started_at       timestamptz NOT NULL,
  ended_at         timestamptz
);
CREATE INDEX battles_world ON battles (world_id);
