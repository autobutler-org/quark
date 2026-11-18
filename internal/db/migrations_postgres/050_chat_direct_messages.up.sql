-- Direct messages (#2423) are chat_channels rows of kind 'dm', which 015
-- already allows. dm_key is the ids of the accounts a direct message was
-- opened with, sorted and joined by commas ("3,7,12"), so opening one with the
-- same people finds the same row. The unique index is what makes two people
-- opening the same conversation at once end up in one. A named channel has
-- none, and a unique index lets any number of NULLs through. The key keeps the
-- id of an account that was since deleted, so the people left behind don't
-- find that history when they open a conversation with each other.
ALTER TABLE chat_channels ADD COLUMN dm_key TEXT;

CREATE UNIQUE INDEX idx_chat_channels_dm_key ON chat_channels (dm_key);
