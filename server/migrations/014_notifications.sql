-- When (and when not) to bother a player. Minutes after local midnight;
-- quiet hours may wrap past midnight. NULL: no quiet hours.
ALTER TABLE accounts
  ADD COLUMN quiet_start integer CHECK (quiet_start BETWEEN 0 AND 1439),
  ADD COLUMN quiet_end integer CHECK (quiet_end BETWEEN 0 AND 1439),
  ADD COLUMN utc_offset_minutes integer NOT NULL DEFAULT 0,
  ADD COLUMN digest_hour integer NOT NULL DEFAULT 18 CHECK (digest_hour BETWEEN 0 AND 23);

-- What happened to a player. 'push' ones are sent to their devices (outside
-- quiet hours); 'digest' ones wait for the daily digest.
CREATE TABLE notifications (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  world_id   bigint NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
  account_id bigint NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
  kind       text NOT NULL,
  tier       text NOT NULL CHECK (tier IN ('push', 'digest')),
  title      text NOT NULL,
  body       text NOT NULL,
  created_at timestamptz NOT NULL,
  read_at    timestamptz,
  pushed_at  timestamptz,
  -- The digest that summed it up.
  digest_id  bigint REFERENCES notifications (id) ON DELETE SET NULL
);
CREATE INDEX notifications_inbox ON notifications (account_id, world_id, created_at DESC);
CREATE INDEX notifications_unpushed ON notifications (created_at) WHERE tier = 'push' AND pushed_at IS NULL;

-- Phones to push to (FCM registration tokens).
CREATE TABLE devices (
  token        text PRIMARY KEY,
  account_id   bigint NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
  platform     text NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX devices_account ON devices (account_id);
