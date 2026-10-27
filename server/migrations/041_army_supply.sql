-- Field armies carry their own grain (sim/supply.ts): what they had at
-- supply_at, when the food ran out once that is settled, and the next time
-- hunger strikes them. Armies from before have no supply (null): their home
-- village feeds them as it did.
ALTER TABLE armies ADD COLUMN supply double precision;
ALTER TABLE armies ADD COLUMN supply_at timestamptz;
ALTER TABLE armies ADD COLUMN hungry_since timestamptz;
ALTER TABLE armies ADD COLUMN hunger_at timestamptz;
-- An army marching into one of its owner's villages to join the garrison.
ALTER TABLE armies DROP CONSTRAINT armies_orders_check;
ALTER TABLE armies ADD CONSTRAINT armies_orders_check CHECK (orders IN ('support', 'reinforce', 'harass', 'hold', 'clear', 'explore', 'garrison'));
