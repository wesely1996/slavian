CREATE TABLE accounts (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  display_name text NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT now()
);

-- Bearer tokens are stored hashed; the plain token only exists on the device.
CREATE TABLE sessions (
  token_hash   bytea PRIMARY KEY,
  account_id   bigint NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
  created_at   timestamptz NOT NULL DEFAULT now(),
  last_used_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE worlds
  ADD COLUMN status          text NOT NULL DEFAULT 'lobby' CHECK (status IN ('lobby', 'running', 'won', 'lost')),
  ADD COLUMN invite_code     text UNIQUE,
  ADD COLUMN host_account_id bigint REFERENCES accounts (id),
  ADD COLUMN max_players     integer NOT NULL DEFAULT 6 CHECK (max_players BETWEEN 1 AND 6),
  ADD COLUMN radius          integer,
  ADD COLUMN active_fronts   text[] NOT NULL DEFAULT '{}',
  ADD COLUMN started_at      timestamptz;

CREATE TABLE world_members (
  world_id   bigint NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
  account_id bigint NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
  joined_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (world_id, account_id)
);
CREATE INDEX world_members_account ON world_members (account_id);

CREATE TABLE hexes (
  world_id bigint NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
  q        integer NOT NULL,
  r        integer NOT NULL,
  terrain  text NOT NULL,
  PRIMARY KEY (world_id, q, r)
);

ALTER TABLE villages ADD COLUMN owner_account_id bigint REFERENCES accounts (id);
CREATE INDEX villages_world ON villages (world_id);
