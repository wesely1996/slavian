-- Ancient sites and lore scrolls (M4 step 1).
CREATE TABLE sites (
  id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  world_id       bigint NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
  kind           text NOT NULL,
  q              integer NOT NULL,
  r              integer NOT NULL,
  -- Who watches it; known to the group once someone has fought them.
  guardians      jsonb NOT NULL DEFAULT '{}',
  guardians_seen boolean NOT NULL DEFAULT false,
  status         text NOT NULL DEFAULT 'unexplored' CHECK (status IN ('unexplored', 'explored')),
  explored_by    bigint REFERENCES accounts (id) ON DELETE SET NULL,
  -- What was found: { type: 'resources' | 'gear' | 'ember' | 'scroll', ... }.
  find           jsonb,
  explored_at    timestamptz,
  UNIQUE (world_id, q, r)
);

-- The group's lore scrolls, each found once.
CREATE TABLE lore (
  world_id   bigint NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
  scroll     text NOT NULL,
  account_id bigint REFERENCES accounts (id) ON DELETE SET NULL,
  site_id    bigint REFERENCES sites (id) ON DELETE SET NULL,
  found_at   timestamptz NOT NULL,
  PRIMARY KEY (world_id, scroll)
);

-- An army fighting a site's guardians.
ALTER TABLE battles ADD COLUMN site_id bigint REFERENCES sites (id) ON DELETE SET NULL;

ALTER TABLE armies DROP CONSTRAINT armies_orders_check;
ALTER TABLE armies ADD CONSTRAINT armies_orders_check CHECK (orders IN ('support', 'reinforce', 'harass', 'hold', 'clear', 'explore'));
