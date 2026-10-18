-- Standing orders, run every few game minutes for their village.
CREATE TABLE standing_orders (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  world_id    bigint NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
  village_id  bigint NOT NULL REFERENCES villages (id) ON DELETE CASCADE,
  -- { kind: 'train', unit, batch, target } | { kind: 'rebuild' } | { kind: 'surplus', share }
  spec        jsonb NOT NULL,
  -- What happened the last time it ran.
  last_result text,
  last_run_at timestamptz,
  created_at  timestamptz NOT NULL
);
CREATE INDEX standing_orders_village ON standing_orders (village_id);
