-- PvP worlds (armies.json pvp): players may attack each other's villages.
-- A village founded in one is safe for pvp.protectionHours from founded_at
-- (older villages have none and are not protected).
ALTER TABLE worlds ADD COLUMN pvp boolean NOT NULL DEFAULT false;
ALTER TABLE villages ADD COLUMN founded_at timestamptz;
-- Orders to attack (plunder) or raze another player's village.
ALTER TABLE armies DROP CONSTRAINT armies_orders_check;
ALTER TABLE armies ADD CONSTRAINT armies_orders_check CHECK (orders IN ('support', 'reinforce', 'harass', 'hold', 'clear', 'explore', 'garrison', 'raid', 'attack', 'raze'));
