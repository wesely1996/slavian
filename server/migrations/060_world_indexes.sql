-- Per-world lookups on tables that had no index starting with world_id
-- (only partial ones, or none): without these every read scans the rows of
-- every world on the server.
CREATE INDEX waves_world ON waves (world_id, status);
CREATE INDEX sites_world ON sites (world_id);
CREATE INDEX forts_world ON forts (world_id);
CREATE INDEX enemy_leaders_world ON enemy_leaders (world_id);
CREATE INDEX standing_orders_world ON standing_orders (world_id);
