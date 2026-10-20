-- Light telemetry (PLAN.md §13): how runs go, for balancing. No personal
-- data: a world's id, counts and outcomes. No foreign key, so the numbers
-- outlive a deleted world.
CREATE TABLE telemetry (
  id       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  world_id bigint NOT NULL,
  kind     text NOT NULL CHECK (kind IN ('run_start', 'run_end', 'wave_result')),
  data     jsonb NOT NULL DEFAULT '{}',
  at       timestamptz NOT NULL
);
CREATE INDEX telemetry_kind_at ON telemetry (kind, at);
