-- Outposts live in villages.plots ("o<q>,<r>" keys). A village under siege
-- gets nothing from its outposts.
ALTER TABLE villages ADD COLUMN besieged boolean NOT NULL DEFAULT false;

-- Hordes burn outposts near their route as they pass.
CREATE TABLE raids (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  world_id    bigint NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
  wave_id     bigint NOT NULL REFERENCES waves (id) ON DELETE CASCADE,
  village_id  bigint NOT NULL REFERENCES villages (id) ON DELETE CASCADE,
  q           integer NOT NULL,
  r           integer NOT NULL,
  level_after integer NOT NULL,
  at          timestamptz NOT NULL
);
CREATE INDEX raids_world ON raids (world_id, at DESC);
