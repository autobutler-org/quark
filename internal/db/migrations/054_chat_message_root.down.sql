DROP INDEX IF EXISTS idx_chat_messages_root;
ALTER TABLE chat_messages DROP COLUMN root_id;
