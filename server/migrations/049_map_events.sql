-- Daily map events (data/events.json): captives held in a camp, and hard
-- ruins; each goes when its time is up unless an army is on its way.
ALTER TABLE camps DROP CONSTRAINT camps_kind_check;
ALTER TABLE camps ADD CONSTRAINT camps_kind_check CHECK (kind IN ('bandit', 'lair', 'captives'));
-- What freeing the captives brings: { units } or { resources }.
ALTER TABLE camps ADD COLUMN reward jsonb;
ALTER TABLE camps ADD COLUMN ends_at timestamptz;
ALTER TABLE sites ADD COLUMN hard boolean NOT NULL DEFAULT false;
ALTER TABLE sites ADD COLUMN ends_at timestamptz;
