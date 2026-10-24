-- Research brought in by a player's Academies, which techs cost: the amount
-- as of the last time it was settled (null: never yet), credited lazily at
-- the rate their villages' Academies give.
ALTER TABLE world_members ADD COLUMN research_points double precision NOT NULL DEFAULT 0;
ALTER TABLE world_members ADD COLUMN research_settled_at timestamptz;
