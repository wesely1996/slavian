-- Releases already announced to every player's phone (push/announce.ts):
-- each version once, however often the server restarts.
CREATE TABLE release_announcements (
  version      text PRIMARY KEY,
  announced_at timestamptz NOT NULL
);
