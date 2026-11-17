-- Merchant caravans (logistics.json merchant): a caravan of its own kind,
-- trading along the road, and when each player may send the next.
ALTER TABLE caravans DROP CONSTRAINT caravans_kind_check;
ALTER TABLE caravans ADD CONSTRAINT caravans_kind_check CHECK (kind IN ('deliver', 'fetch', 'merchant'));
ALTER TABLE world_members ADD COLUMN merchant_ready_at timestamptz;
