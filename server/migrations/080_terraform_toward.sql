-- A river dug along a hex's edge (field.json terraform river): the
-- neighbouring hex it runs toward.
ALTER TABLE terraforms ADD COLUMN tq integer;
ALTER TABLE terraforms ADD COLUMN tr integer;
