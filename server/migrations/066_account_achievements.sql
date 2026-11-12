-- Achievements belong to the account: what a player earned in solo runs on
-- their device, sent once they are signed in (the server's own runs are in
-- `achievements`). `runs`: how many solo runs it came up in.
CREATE TABLE solo_achievements (
  account_id  bigint NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
  achievement text NOT NULL,
  earned_at   timestamptz NOT NULL,
  runs        integer NOT NULL DEFAULT 1,
  PRIMARY KEY (account_id, achievement)
);
