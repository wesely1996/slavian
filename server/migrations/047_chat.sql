-- The group chat: one per world (db/chat.ts), with the sender's name as it
-- was when they wrote. A deleted account takes its messages with it.
CREATE TABLE chat_messages (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  world_id    bigint NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
  account_id  bigint NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
  name        text NOT NULL,
  body        text NOT NULL,
  created_at  timestamptz NOT NULL
);
CREATE INDEX chat_messages_world ON chat_messages (world_id, id DESC);

-- How far each player has read.
CREATE TABLE chat_reads (
  world_id    bigint NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
  account_id  bigint NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
  last_read_id bigint NOT NULL,
  PRIMARY KEY (world_id, account_id)
);
