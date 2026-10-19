-- Onboarding (M4 step 6): each member's getting-started steps done, step -> when.
ALTER TABLE world_members ADD COLUMN onboarding jsonb NOT NULL DEFAULT '{}';
