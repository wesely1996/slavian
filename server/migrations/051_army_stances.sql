-- Every army fights in its own stance (data/battle.json), and breaks on
-- its own losses since it joined a battle (engaged_units: what it had then).
ALTER TABLE armies ADD COLUMN stance text NOT NULL DEFAULT 'balanced';
ALTER TABLE armies ADD COLUMN engaged_units jsonb;
-- Armies already out keep fighting the way they did: in their village's stance.
UPDATE armies SET stance = villages.stance FROM villages WHERE villages.id = armies.home_village_id;
