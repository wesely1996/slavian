-- Cultists of Černobog working a ritual (events.json ritual): a camp of
-- their own kind, its ritual ending at ends_at.
ALTER TABLE camps DROP CONSTRAINT camps_kind_check;
ALTER TABLE camps ADD CONSTRAINT camps_kind_check CHECK (kind IN ('bandit', 'lair', 'captives', 'cultists'));
