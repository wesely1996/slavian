-- Difficulty as hereditary titles (data/difficulty.json), easiest first:
-- baron (the old normal), viscount (old hard), count (old nightmare),
-- marquess and duke (new). The old story is gone: its worlds become baron.
ALTER TABLE worlds DROP CONSTRAINT IF EXISTS worlds_difficulty_check;
UPDATE worlds SET difficulty = CASE difficulty
  WHEN 'story' THEN 'baron'
  WHEN 'normal' THEN 'baron'
  WHEN 'hard' THEN 'viscount'
  WHEN 'nightmare' THEN 'count'
  ELSE difficulty END;
ALTER TABLE worlds ALTER COLUMN difficulty SET DEFAULT 'baron';
ALTER TABLE worlds ADD CONSTRAINT worlds_difficulty_check CHECK (difficulty IN ('baron', 'viscount', 'count', 'marquess', 'duke'));
