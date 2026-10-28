-- Supply points (forts of kind 'supply') and the grain forts and supply
-- points keep for armies standing on them (data/field.json). Caravans on a
-- supply route deliver into one (destination_fort_id; the fort may be gone
-- by the time they arrive, so no foreign key).
ALTER TABLE forts ADD COLUMN kind text NOT NULL DEFAULT 'fort' CHECK (kind IN ('fort', 'supply'));
ALTER TABLE forts ADD COLUMN grain double precision NOT NULL DEFAULT 0;
ALTER TABLE caravans ADD COLUMN destination_fort_id bigint;
