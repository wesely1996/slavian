-- The Holy City vault: one per world, shared by the group.
CREATE TABLE vaults (
  world_id             bigint PRIMARY KEY REFERENCES worlds (id) ON DELETE CASCADE,
  level                integer NOT NULL DEFAULT 1,
  amounts              jsonb NOT NULL DEFAULT '{"wood": 0, "stone": 0, "grain": 0, "iron": 0}',
  upgrading_to         integer,
  upgrade_completes_at timestamptz
);

-- A caravan trip: out to a village or the vault and back home.
CREATE TABLE caravans (
  id                     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  world_id               bigint NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
  village_id             bigint NOT NULL REFERENCES villages (id) ON DELETE CASCADE,
  -- NULL: the Holy City vault.
  destination_village_id bigint REFERENCES villages (id) ON DELETE CASCADE,
  kind                   text NOT NULL CHECK (kind IN ('deliver', 'fetch')),
  caravans               integer NOT NULL CHECK (caravans > 0),
  -- deliver: what it set out with; fetch: what it was sent for.
  cargo                  jsonb NOT NULL,
  -- What it carries home (leftovers, or what it fetched).
  carried_back           jsonb,
  status                 text NOT NULL DEFAULT 'outbound' CHECK (status IN ('outbound', 'returning', 'done')),
  path                   jsonb NOT NULL,
  departs_at             timestamptz NOT NULL,
  arrives_at             timestamptz NOT NULL,
  returns_at             timestamptz NOT NULL
);
CREATE INDEX caravans_world ON caravans (world_id, status);
CREATE INDEX caravans_village ON caravans (village_id) WHERE status <> 'done';
