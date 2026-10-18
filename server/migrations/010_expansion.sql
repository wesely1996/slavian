-- Grain per hour (world speed 1) a founded village pays for administration.
ALTER TABLE villages ADD COLUMN admin_upkeep real NOT NULL DEFAULT 0;

-- Settlers on their way to found a village (or coming back when they can't).
CREATE TABLE expeditions (
  id                 bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  world_id           bigint NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
  village_id         bigint NOT NULL REFERENCES villages (id) ON DELETE CASCADE,
  q                  integer NOT NULL,
  r                  integer NOT NULL,
  name               text NOT NULL,
  settlers           integer NOT NULL CHECK (settlers > 0),
  status             text NOT NULL DEFAULT 'outbound' CHECK (status IN ('outbound', 'returning', 'founded', 'done')),
  -- Why they came back, when they did.
  failure            text,
  founded_village_id bigint REFERENCES villages (id) ON DELETE SET NULL,
  path               jsonb NOT NULL,
  departs_at         timestamptz NOT NULL,
  arrives_at         timestamptz NOT NULL,
  returns_at         timestamptz NOT NULL
);
CREATE INDEX expeditions_world ON expeditions (world_id, status);
