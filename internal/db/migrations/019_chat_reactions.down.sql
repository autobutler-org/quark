UPDATE chat_channel_members SET permissions = permissions & ~64;
DROP TRIGGER IF EXISTS chat_reactions_tombstone;
DROP TABLE IF EXISTS chat_reactions;
