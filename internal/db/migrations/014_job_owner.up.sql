-- A job records the account that queued it (#1979), so only that account and
-- admins see it, and it runs with that account's access. Deleting the account
-- deletes its jobs.
--
-- Existing jobs keep a NULL owner, as does a job queued by the system, and are
-- shown to admins only. SQLite only lets ADD COLUMN add a foreign key whose
-- default is NULL, so the column stays nullable.
ALTER TABLE jobs
ADD COLUMN user_id INTEGER REFERENCES users (id) ON DELETE CASCADE;
