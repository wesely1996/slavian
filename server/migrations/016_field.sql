-- Battles can be fought on open ground (no village), at a hex.
ALTER TABLE battles
  ALTER COLUMN village_id DROP NOT NULL,
  ADD COLUMN q integer,
  ADD COLUMN r integer,
  -- What the ground gave the defenders: { ambush, choke, fort }.
  ADD COLUMN setup jsonb NOT NULL DEFAULT '{}';
UPDATE battles b SET q = v.q, r = v.r FROM villages v WHERE v.id = b.village_id;

-- Armies can hold a hex; a hero can lead one.
ALTER TABLE armies
  ALTER COLUMN target_village_id DROP NOT NULL,
  ADD COLUMN target_q integer,
  ADD COLUMN target_r integer,
  ADD COLUMN hero_account_id bigint REFERENCES accounts (id) ON DELETE SET NULL;
UPDATE armies a SET target_q = v.q, target_r = v.r FROM villages v WHERE v.id = a.target_village_id;
ALTER TABLE armies DROP CONSTRAINT armies_orders_check;
ALTER TABLE armies ADD CONSTRAINT armies_orders_check CHECK (orders IN ('support', 'reinforce', 'harass', 'hold'));
CREATE INDEX armies_hex ON armies (world_id, target_q, target_r) WHERE status IN ('stationed', 'engaged');

ALTER TABLE heroes DROP CONSTRAINT heroes_status_check;
ALTER TABLE heroes ADD CONSTRAINT heroes_status_check CHECK (status IN ('home', 'traveling', 'wounded', 'with_army'));
ALTER TABLE heroes ADD COLUMN army_id bigint REFERENCES armies (id) ON DELETE SET NULL;

CREATE TABLE forts (
  id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  world_id         bigint NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
  owner_account_id bigint REFERENCES accounts (id) ON DELETE SET NULL,
  village_id       bigint REFERENCES villages (id) ON DELETE SET NULL,
  q                integer NOT NULL,
  r                integer NOT NULL,
  status           text NOT NULL DEFAULT 'building' CHECK (status IN ('building', 'standing')),
  completes_at     timestamptz NOT NULL,
  UNIQUE (world_id, q, r)
);
