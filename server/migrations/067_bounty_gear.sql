-- A bounty can offer gear from the poster's hero's pack too (item ids, held
-- off the hero while it stands; equipped gear can't be offered).
ALTER TABLE bounties ADD COLUMN items jsonb NOT NULL DEFAULT '[]';
