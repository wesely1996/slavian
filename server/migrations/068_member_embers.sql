-- Svarog's Embers belong to each player (who found them), not to the group.
-- What a world held is shared out among its members, any left over to the
-- first to have joined.
ALTER TABLE world_members ADD COLUMN embers integer NOT NULL DEFAULT 0;

WITH counted AS (
  SELECT m.world_id, m.account_id, w.embers AS total,
         count(*) OVER (PARTITION BY m.world_id) AS members,
         row_number() OVER (PARTITION BY m.world_id ORDER BY m.joined_at, m.account_id) AS place
  FROM world_members m JOIN worlds w ON w.id = m.world_id
  WHERE m.left_at IS NULL AND w.embers > 0
)
UPDATE world_members m
SET embers = (c.total / c.members) + CASE WHEN c.place <= c.total % c.members THEN 1 ELSE 0 END
FROM counted c
WHERE m.world_id = c.world_id AND m.account_id = c.account_id;

UPDATE worlds SET embers = 0;
