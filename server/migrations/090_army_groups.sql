-- Army groups (data/armies.json groups): a named army with a set
-- composition. Until its army stands, the troops gather at its home
-- settlement; missing ones are trained in the owner's closest settlement and
-- march to it. `army_id` is the army it fields (null: none yet). An army
-- marching to join a group carries its id (`armies.group_id`).
CREATE TABLE army_groups (
  id bigserial PRIMARY KEY,
  world_id bigint NOT NULL REFERENCES worlds(id) ON DELETE CASCADE,
  owner_account_id bigint NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  name text NOT NULL,
  composition jsonb NOT NULL,
  home_village_id bigint NOT NULL REFERENCES villages(id) ON DELETE CASCADE,
  army_id bigint REFERENCES armies(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL
);
CREATE INDEX army_groups_world ON army_groups (world_id);
ALTER TABLE armies ADD COLUMN group_id bigint REFERENCES army_groups(id) ON DELETE SET NULL;
