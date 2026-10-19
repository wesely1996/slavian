-- The Kalinov Bridge (M4 step 2): one per world, its state as JSON (see sim/bridge.ts).
CREATE TABLE bridges (
  world_id bigint PRIMARY KEY REFERENCES worlds (id) ON DELETE CASCADE,
  state    jsonb NOT NULL
);
