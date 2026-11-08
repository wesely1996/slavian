-- An army told to come home once its errand is done: a village reached, a
-- camp cleared, a site searched, a shipyard's boat finished.
ALTER TABLE armies ADD COLUMN return_home boolean NOT NULL DEFAULT false;
