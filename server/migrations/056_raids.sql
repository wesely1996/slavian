-- An army on a raid beyond the map's edge (data/raids.json): the front, how
-- many fields deep it goes, the stage it has reached, and its battles.
ALTER TABLE armies ADD COLUMN raid jsonb;
ALTER TABLE armies DROP CONSTRAINT armies_orders_check;
ALTER TABLE armies ADD CONSTRAINT armies_orders_check CHECK (orders IN ('support', 'reinforce', 'harass', 'hold', 'clear', 'explore', 'garrison', 'raid'));
