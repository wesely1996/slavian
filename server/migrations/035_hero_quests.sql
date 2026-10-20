-- Hero quests (M5 step 22): a hero away on a quest (status 'questing'), the
-- quest it is on, and the offers it already took (so they aren't offered again).
ALTER TABLE heroes DROP CONSTRAINT heroes_status_check;
ALTER TABLE heroes ADD CONSTRAINT heroes_status_check CHECK (status IN ('home', 'traveling', 'wounded', 'with_army', 'questing'));
ALTER TABLE heroes ADD COLUMN quest jsonb;
ALTER TABLE heroes ADD COLUMN quests_done jsonb NOT NULL DEFAULT '[]';
