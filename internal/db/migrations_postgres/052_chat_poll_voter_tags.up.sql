-- The PostgreSQL half of 052_chat_poll_voter_tags: an anonymous poll's answer
-- holds a voter tag instead of user_id (#3942). The anonymous answers already
-- stored keep user_id until the server converts them at start.
ALTER TABLE chat_poll_answers ALTER COLUMN user_id DROP NOT NULL;
ALTER TABLE chat_poll_answers ADD COLUMN voter_tag BYTEA;
ALTER TABLE chat_poll_answers ADD CONSTRAINT chat_poll_answers_message_id_voter_tag_key UNIQUE (message_id, voter_tag);
ALTER TABLE chat_poll_answers ADD CONSTRAINT chat_poll_answers_one_voter CHECK ((user_id IS NULL) <> (voter_tag IS NULL));
