-- The enemy lands beyond the edge (enemy-lands.json): how many bands of each
-- front the players have seen (beyond that, fog). Absent: the starting sight.
ALTER TABLE worlds ADD COLUMN enemy_sight jsonb NOT NULL DEFAULT '{}'::jsonb;
