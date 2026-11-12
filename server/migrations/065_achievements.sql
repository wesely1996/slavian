-- Achievements (data/achievements.json): what each player earned in a run,
-- and when, in the order earned.
CREATE TABLE achievements (
  id          bigserial PRIMARY KEY,
  world_id    bigint NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
  account_id  bigint NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
  achievement text NOT NULL,
  earned_at   timestamptz NOT NULL,
  UNIQUE (world_id, account_id, achievement)
);
CREATE INDEX achievements_account ON achievements (account_id);
