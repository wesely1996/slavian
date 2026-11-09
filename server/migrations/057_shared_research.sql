-- Research is the group's (data/research.json): one tech at a time for the
-- whole world. A member starts it (the row keeps who, and from which
-- village); while 'funding' the members send its resources (paid) until its
-- cost is met, then it is 'researching' until completes_at. Research begun
-- per player before this finishes as it was.
ALTER TABLE research DROP CONSTRAINT research_status_check;
ALTER TABLE research ADD CONSTRAINT research_status_check CHECK (status IN ('funding', 'researching', 'done'));
ALTER TABLE research ADD COLUMN cost jsonb;
ALTER TABLE research ADD COLUMN paid jsonb;
DROP INDEX research_one_at_a_time;
CREATE UNIQUE INDEX research_one_funding ON research (world_id) WHERE status = 'funding';
