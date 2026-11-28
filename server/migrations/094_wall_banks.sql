-- A river edge holds a wall on each bank (data/field.json edgeWalls): side
-- 0 is a wall along a dry edge, 1 and 2 stand on the bank of the edge's
-- first and second hex (aq, ar / bq, br).
ALTER TABLE edge_walls ADD COLUMN side smallint NOT NULL DEFAULT 0 CHECK (side IN (0, 1, 2));
ALTER TABLE edge_walls DROP CONSTRAINT edge_walls_pkey;
ALTER TABLE edge_walls ADD PRIMARY KEY (world_id, aq, ar, bq, br, side);
