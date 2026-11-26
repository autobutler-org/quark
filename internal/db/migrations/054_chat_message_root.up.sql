-- A side conversation (#4345) is a set of replies to one channel message, the
-- root. root_id names it in the clear, so the Quark learns which messages
-- branch from which and never what they say. A channel message has none, and
-- a reply never has a root that is itself a reply: chatutil refuses that, one
-- level deep. Deleting a root leaves a tombstone row, so the reference holds;
-- the cascade only fires when the whole channel goes.
ALTER TABLE chat_messages ADD COLUMN root_id INTEGER REFERENCES chat_messages (id) ON DELETE CASCADE;

CREATE INDEX idx_chat_messages_root ON chat_messages (root_id, id);
