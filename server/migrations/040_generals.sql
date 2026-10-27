-- Generals: lesser heroes recruited at a Hero's Hall. They stand in a
-- village (commanding its garrison), travel between villages and lead
-- armies; one whose side loses a battle is killed.
CREATE TABLE generals (
  id             bigserial PRIMARY KEY,
  world_id       bigint NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
  account_id     bigint NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
  name           text NOT NULL,
  status         text NOT NULL CHECK (status IN ('recruiting', 'home', 'traveling', 'with_army')),
  -- Where it stands (or is recruited, or heading).
  village_id     bigint REFERENCES villages (id) ON DELETE SET NULL,
  level          integer NOT NULL DEFAULT 1,
  xp             integer NOT NULL DEFAULT 0,
  army_id        bigint REFERENCES armies (id) ON DELETE SET NULL,
  path           jsonb,
  departs_at     timestamptz,
  -- Ready (recruiting) or arriving (traveling).
  until          timestamptz
);
CREATE INDEX generals_world ON generals (world_id);

ALTER TABLE armies ADD COLUMN general_id bigint REFERENCES generals (id) ON DELETE SET NULL;
