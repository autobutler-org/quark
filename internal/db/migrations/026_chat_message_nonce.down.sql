-- The replays 026 turned into tombstones stay that way: their ciphertext is gone.
DROP INDEX IF EXISTS idx_chat_messages_nonce;
ALTER TABLE chat_messages DROP COLUMN nonce;
