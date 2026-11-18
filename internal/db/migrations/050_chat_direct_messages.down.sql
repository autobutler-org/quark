DROP INDEX IF EXISTS idx_chat_channels_dm_key;
ALTER TABLE chat_channels DROP COLUMN dm_key;
