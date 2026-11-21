-- How far an army, or a village's garrison, maneuvers in battle at most
-- (battle.json lines): none, flank, pincer or encircle.
ALTER TABLE armies ADD COLUMN maneuver text NOT NULL DEFAULT 'encircle' CHECK (maneuver IN ('none', 'flank', 'pincer', 'encircle'));
ALTER TABLE villages ADD COLUMN maneuver text NOT NULL DEFAULT 'encircle' CHECK (maneuver IN ('none', 'flank', 'pincer', 'encircle'));
