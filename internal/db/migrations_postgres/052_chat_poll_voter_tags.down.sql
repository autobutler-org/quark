-- A tagged answer cannot be traced back to its account, so it goes.
DELETE FROM chat_poll_answers WHERE user_id IS NULL;
ALTER TABLE chat_poll_answers DROP CONSTRAINT chat_poll_answers_one_voter;
ALTER TABLE chat_poll_answers DROP CONSTRAINT chat_poll_answers_message_id_voter_tag_key;
ALTER TABLE chat_poll_answers DROP COLUMN voter_tag;
ALTER TABLE chat_poll_answers ALTER COLUMN user_id SET NOT NULL;
