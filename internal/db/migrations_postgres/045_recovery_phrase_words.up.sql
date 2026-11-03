-- How many words the recovery phrase behind recovery_key_hash had (#3183).
-- The Quark never sees the phrase, so the client says when it sends the key.
-- 0 means unknown: a key stored before #3183, or by an app that did not say.
-- It reads as short, the same as a 6-word phrase from before #3141.
ALTER TABLE users ADD COLUMN recovery_phrase_words BIGINT NOT NULL DEFAULT 0;
