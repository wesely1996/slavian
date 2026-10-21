-- Getting started made claimable (M5 step 23): a step's reward waits until
-- the player claims it (step -> when; 'finale' for the chain's own reward).
-- Steps done before this were rewarded at once, so they count as claimed.
ALTER TABLE world_members ADD COLUMN onboarding_claimed jsonb NOT NULL DEFAULT '{}';
UPDATE world_members SET onboarding_claimed = onboarding;
