DROP INDEX IF EXISTS idx_chat_attachments_message;
DROP INDEX IF EXISTS idx_chat_attachments_channel;
DROP TABLE IF EXISTS chat_attachments;
UPDATE chat_channel_members SET permissions = permissions & ~128;
