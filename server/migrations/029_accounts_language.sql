-- The player's language, so server notices (push and inbox) can be rendered in
-- it. Reported by the app; 'en' until it is (docs/localization.md).
ALTER TABLE accounts ADD COLUMN language text NOT NULL DEFAULT 'en';
