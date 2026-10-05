-- The client derives a recovery key from the recovery phrase and the account's
-- auth salt and sends that instead of the phrase (#2430). recovery_key_hash is
-- the bcrypt hash of that key. An empty one is an account still recovered by
-- its raw phrase; setting it clears recovery_phrase_hash, so the old phrase
-- stops working.
ALTER TABLE users ADD COLUMN recovery_key_hash TEXT NOT NULL DEFAULT '';
