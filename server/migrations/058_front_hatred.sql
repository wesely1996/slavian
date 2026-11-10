-- Hatred belongs to a side (front), not to one horde (data/horde.json
-- `hatred`): ambushes, harassment, raids, strikes and failed events add to
-- the front's hatred, and the next horde of that front to set out takes it
-- all (waves.hatred is then what it carries). Scheduled hordes' hatred so
-- far moves to their front.
ALTER TABLE worlds ADD COLUMN hatred jsonb NOT NULL DEFAULT '{}'::jsonb;
UPDATE worlds w SET hatred = s.hatred
FROM (
  SELECT world_id, jsonb_object_agg(front, total) AS hatred
  FROM (SELECT world_id, front, sum(hatred) AS total FROM waves WHERE status = 'scheduled' AND band_of IS NULL AND hatred > 0 GROUP BY world_id, front) t
  GROUP BY world_id
) s
WHERE s.world_id = w.id;
UPDATE waves SET hatred = 0 WHERE status = 'scheduled';
