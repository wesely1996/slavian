-- Rivers merge (M5 step 19): an edge's size is 1 for a river from its source,
-- plus 1 for each river that joined it above.
ALTER TABLE river_edges ADD COLUMN size smallint NOT NULL DEFAULT 1;
