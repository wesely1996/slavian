-- A river dug across a road (field.json terraform river) comes with a bridge
-- over it, paid for when the work starts.
ALTER TABLE terraforms ADD COLUMN bridge boolean NOT NULL DEFAULT false;
