-- A world's terrain in one compact row instead of a row per hex (it never
-- changes once the map is made, and is always read whole). `cells` holds
-- runs of hexes along a row: "r:q0:t,t,t" for the hexes (q0, r), (q0+1, r)
-- and so on, runs joined by ";" in (r, q) order (db/worlds.ts).
CREATE TABLE world_terrain (
  world_id bigint PRIMARY KEY REFERENCES worlds (id) ON DELETE CASCADE,
  cells    text NOT NULL
);
INSERT INTO world_terrain (world_id, cells)
SELECT world_id, string_agg(run, ';' ORDER BY r, q0)
FROM (
  SELECT world_id, r, min(q) AS q0, r || ':' || min(q) || ':' || string_agg(terrain, ',' ORDER BY q) AS run
  FROM (SELECT world_id, q, r, terrain, q - row_number() OVER (PARTITION BY world_id, r ORDER BY q) AS run_id FROM hexes) h
  GROUP BY world_id, r, run_id
) runs
GROUP BY world_id;
DROP TABLE hexes;
