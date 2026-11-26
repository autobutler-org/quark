-- The PostgreSQL half of 054_chat_message_root: a side conversation's reply
-- names its root message in the clear (#4345).
ALTER TABLE chat_messages ADD COLUMN root_id BIGINT REFERENCES chat_messages (id) ON DELETE CASCADE;

CREATE INDEX idx_chat_messages_root ON chat_messages (root_id, id);
