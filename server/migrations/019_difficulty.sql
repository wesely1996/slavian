-- Difficulty presets and the group's quiet hours (M3 step 6).
ALTER TABLE worlds
  ADD COLUMN difficulty text NOT NULL DEFAULT 'normal' CHECK (difficulty IN ('story', 'normal', 'hard', 'nightmare')),
  -- Hordes don't arrive in this window (minutes after the group's local
  -- midnight, at quiet_utc_offset); null: no quiet hours.
  ADD COLUMN quiet_start integer,
  ADD COLUMN quiet_end integer,
  ADD COLUMN quiet_utc_offset integer NOT NULL DEFAULT 0;
