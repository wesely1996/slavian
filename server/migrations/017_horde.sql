-- Horde AI (M3 step 4): the rampage clock, raid or raze, ruins, fear,
-- bandit camps from horde survivors and the Holy City's Sanctity.
ALTER TABLE waves DROP CONSTRAINT waves_status_check;
ALTER TABLE waves ADD CONSTRAINT waves_status_check
  CHECK (status IN ('scheduled', 'marching', 'arrived', 'battling', 'razing', 'defeated', 'dispersed', 'settled'));
ALTER TABLE waves
  -- Starts when the horde first reaches a target; it roams until then.
  ADD COLUMN rampage_ends_at timestamptz,
  -- Villages it has already struck.
  ADD COLUMN struck bigint[] NOT NULL DEFAULT '{}',
  -- First numbers, for raid recruits and the raze decision.
  ADD COLUMN initial jsonb;
UPDATE waves SET initial = composition;

-- What the horde decided after winning: { choice: 'raid' | 'raze', reasons }.
ALTER TABLE battles ADD COLUMN decision jsonb;

-- A razed village: what stood (plots) and, while rebuilding, when it is done.
ALTER TABLE villages ADD COLUMN ruin jsonb;
-- A refugee camp (the safety net): hordes raid it but never raze it.
ALTER TABLE villages ADD COLUMN refuge boolean NOT NULL DEFAULT false;

ALTER TABLE worlds ADD COLUMN sanctity integer NOT NULL DEFAULT 100;

-- Where hordes were beaten; they avoid it while the memory lasts.
CREATE TABLE fear (
  world_id bigint NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
  q        integer NOT NULL,
  r        integer NOT NULL,
  value    double precision NOT NULL,
  PRIMARY KEY (world_id, q, r)
);

-- Bandit camps and monster lairs (grown and cleared in step 5).
CREATE TABLE camps (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  world_id   bigint NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
  kind       text NOT NULL CHECK (kind IN ('bandit', 'lair')),
  front      text NOT NULL,
  q          integer NOT NULL,
  r          integer NOT NULL,
  units      jsonb NOT NULL,
  status     text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'cleared')),
  -- Where it came from: a wave's survivors, a spawn, an abandoned fort.
  wave_id    bigint REFERENCES waves (id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL
);
CREATE INDEX camps_world ON camps (world_id, status);
