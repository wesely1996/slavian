-- Scouts searching the land around their village for a forgotten ruin
-- (data/scouting.json `ruinSearch`): out until returns_at, then done, with
-- the site they found (if any).
CREATE TABLE ruin_searches (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  world_id      bigint NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
  village_id    bigint NOT NULL REFERENCES villages (id) ON DELETE CASCADE,
  scouts        integer NOT NULL CHECK (scouts > 0),
  status        text NOT NULL DEFAULT 'out' CHECK (status IN ('out', 'done')),
  departs_at    timestamptz NOT NULL,
  returns_at    timestamptz NOT NULL,
  found_site_id bigint REFERENCES sites (id) ON DELETE SET NULL
);
CREATE INDEX ruin_searches_world ON ruin_searches (world_id);
