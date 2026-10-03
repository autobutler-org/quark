-- A message's nonce is stored once per channel and key version (#2487). The
-- additional data binds a ciphertext to its channel and key version but not
-- to one post, so before this the Quark took the same ciphertext twice and
-- showed it as two messages. nonce is the first 24 bytes of ciphertext, kept
-- when a message is deleted so a deleted message can't be replayed either.
-- Tombstones from before this have no nonce, and a unique index lets any
-- number of NULLs through.
ALTER TABLE chat_messages ADD COLUMN nonce BLOB;

-- Replays already stored: the first post of each nonce stays, and every later
-- one becomes a tombstone, which keeps ids contiguous for paging and takes its
-- reactions with it (chat_reactions_tombstone, 019).
UPDATE chat_messages
SET ciphertext = NULL, deleted_at = COALESCE(deleted_at, datetime('now'))
WHERE ciphertext IS NOT NULL AND EXISTS (
    SELECT 1 FROM chat_messages AS earlier
    WHERE earlier.channel_id = chat_messages.channel_id
      AND earlier.key_version = chat_messages.key_version
      AND substr(earlier.ciphertext, 1, 24) = substr(chat_messages.ciphertext, 1, 24)
      AND earlier.id < chat_messages.id
);

UPDATE chat_messages SET nonce = substr(ciphertext, 1, 24) WHERE ciphertext IS NOT NULL;

CREATE UNIQUE INDEX idx_chat_messages_nonce ON chat_messages (channel_id, key_version, nonce);
