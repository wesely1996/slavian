-- Deleting an account (DELETE /v1/me) leaves the worlds it hosted and the
-- villages it owned standing, without an owner, like those of a player who
-- left; everything else of the account already cascades or is set null.
ALTER TABLE worlds DROP CONSTRAINT worlds_host_account_id_fkey,
  ADD CONSTRAINT worlds_host_account_id_fkey FOREIGN KEY (host_account_id) REFERENCES accounts (id) ON DELETE SET NULL;
ALTER TABLE villages DROP CONSTRAINT villages_owner_account_id_fkey,
  ADD CONSTRAINT villages_owner_account_id_fkey FOREIGN KEY (owner_account_id) REFERENCES accounts (id) ON DELETE SET NULL;
