-- Chat polls (#3893). The Quark enforces a poll's settings and stores its
-- answers as ciphertext it never opens.

-- name: CreateChatPoll :exec
INSERT INTO chat_polls (message_id, closes_at, allow_change, anonymous, results_after_close)
VALUES (sqlc.arg(message_id), sqlc.arg(closes_at), sqlc.arg(allow_change), sqlc.arg(anonymous), sqlc.arg(results_after_close));

-- name: GetChatPoll :one
SELECT * FROM chat_polls WHERE message_id = sqlc.arg(message_id);

-- CloseChatPoll closes a poll by hand, once: a poll already closed keeps its
-- first closed_at and the count is 0.
-- name: CloseChatPoll :execrows
UPDATE chat_polls SET closed_at = strftime('%Y-%m-%d %H:%M:%f', 'now')
WHERE message_id = sqlc.arg(message_id) AND closed_at IS NULL;

-- ListChatPollsBetween is the polls among a channel's messages whose ids fall
-- in [first_id, last_id], one page of ListChatMessages*.
-- name: ListChatPollsBetween :many
SELECT chat_polls.*
FROM chat_polls
JOIN chat_messages ON chat_messages.id = chat_polls.message_id
WHERE chat_messages.channel_id = sqlc.arg(channel_id)
  AND chat_polls.message_id >= sqlc.arg(first_id)
  AND chat_polls.message_id <= sqlc.arg(last_id)
ORDER BY chat_polls.message_id;

-- SetChatPollAnswer stores or replaces an account's answer to a poll that
-- names who answered and still exists, and returns no row once the poll went
-- with its message.
-- name: SetChatPollAnswer :one
INSERT INTO chat_poll_answers (message_id, user_id, key_version, ciphertext)
SELECT message_id, CAST(sqlc.arg(user_id) AS BIGINT), sqlc.arg(key_version), sqlc.arg(ciphertext)
FROM chat_polls
WHERE chat_polls.message_id = sqlc.arg(message_id)
ON CONFLICT (message_id, user_id) DO UPDATE SET
    key_version = excluded.key_version,
    ciphertext = excluded.ciphertext,
    updated_at = strftime('%Y-%m-%d %H:%M:%f', 'now')
RETURNING *;

-- CreateChatPollAnswer stores an account's first answer to a poll that names
-- who answered, and returns no row when it already answered or the poll is
-- gone.
-- name: CreateChatPollAnswer :one
INSERT INTO chat_poll_answers (message_id, user_id, key_version, ciphertext)
SELECT message_id, CAST(sqlc.arg(user_id) AS BIGINT), sqlc.arg(key_version), sqlc.arg(ciphertext)
FROM chat_polls
WHERE chat_polls.message_id = sqlc.arg(message_id)
ON CONFLICT (message_id, user_id) DO NOTHING
RETURNING *;

-- SetChatPollAnonymousAnswer is SetChatPollAnswer for an anonymous poll: the
-- row holds the account's voter tag and no user_id (#3942).
-- name: SetChatPollAnonymousAnswer :one
INSERT INTO chat_poll_answers (message_id, voter_tag, key_version, ciphertext)
SELECT message_id, sqlc.arg(voter_tag), sqlc.arg(key_version), sqlc.arg(ciphertext)
FROM chat_polls
WHERE chat_polls.message_id = sqlc.arg(message_id)
ON CONFLICT (message_id, voter_tag) DO UPDATE SET
    key_version = excluded.key_version,
    ciphertext = excluded.ciphertext,
    updated_at = strftime('%Y-%m-%d %H:%M:%f', 'now')
RETURNING *;

-- CreateChatPollAnonymousAnswer is CreateChatPollAnswer for an anonymous
-- poll: the row holds the account's voter tag and no user_id (#3942).
-- name: CreateChatPollAnonymousAnswer :one
INSERT INTO chat_poll_answers (message_id, voter_tag, key_version, ciphertext)
SELECT message_id, sqlc.arg(voter_tag), sqlc.arg(key_version), sqlc.arg(ciphertext)
FROM chat_polls
WHERE chat_polls.message_id = sqlc.arg(message_id)
ON CONFLICT (message_id, voter_tag) DO NOTHING
RETURNING *;

-- ListUntaggedAnonymousChatPollAnswers is the answers to anonymous polls that
-- still name their account: stored before migration 052, and converted once
-- at start (#3942).
-- name: ListUntaggedAnonymousChatPollAnswers :many
SELECT chat_poll_answers.id, chat_poll_answers.message_id, chat_poll_answers.user_id
FROM chat_poll_answers
JOIN chat_polls ON chat_polls.message_id = chat_poll_answers.message_id
WHERE chat_polls.anonymous = TRUE AND chat_poll_answers.user_id IS NOT NULL
ORDER BY chat_poll_answers.id;

-- TagChatPollAnswer swaps an anonymous answer's user_id for its voter tag.
-- name: TagChatPollAnswer :exec
UPDATE chat_poll_answers SET voter_tag = sqlc.arg(voter_tag), user_id = NULL
WHERE id = sqlc.arg(id);

-- name: DeleteChatPollAnswer :exec
DELETE FROM chat_poll_answers WHERE id = sqlc.arg(id);

-- ListAnonymousChatPollIDs is every anonymous poll, for removing a deleted
-- account's answers by their voter tags.
-- name: ListAnonymousChatPollIDs :many
SELECT message_id FROM chat_polls WHERE anonymous = TRUE ORDER BY message_id;

-- name: DeleteChatPollAnswerByVoterTag :exec
DELETE FROM chat_poll_answers
WHERE message_id = sqlc.arg(message_id) AND voter_tag = sqlc.arg(voter_tag);

-- name: ListChatPollAnswers :many
SELECT * FROM chat_poll_answers WHERE message_id = sqlc.arg(message_id) ORDER BY id;

-- ListChatPollAnswersBetween is the answers to a channel's polls whose ids
-- fall in [first_id, last_id], one page of ListChatMessages*.
-- name: ListChatPollAnswersBetween :many
SELECT chat_poll_answers.*
FROM chat_poll_answers
JOIN chat_messages ON chat_messages.id = chat_poll_answers.message_id
WHERE chat_messages.channel_id = sqlc.arg(channel_id)
  AND chat_poll_answers.message_id >= sqlc.arg(first_id)
  AND chat_poll_answers.message_id <= sqlc.arg(last_id)
ORDER BY chat_poll_answers.id;
