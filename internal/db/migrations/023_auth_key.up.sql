-- An account can sign in with a key its client derives from the password
-- instead of the password itself (#2430). auth_salt is the base64 salt that
-- derivation uses and auth_key_hash the bcrypt hash of the key. An empty
-- auth_key_hash is an account that has not been upgraded; an account made
-- with a key has an empty password_hash, which no password matches.
ALTER TABLE users ADD COLUMN auth_salt TEXT NOT NULL DEFAULT '';

ALTER TABLE users ADD COLUMN auth_key_hash TEXT NOT NULL DEFAULT '';
