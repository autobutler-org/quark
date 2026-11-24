-- The PostgreSQL half of 055_chat_branch_read_markers: how far each account
-- has read in each side conversation (#4349).
CREATE TABLE chat_branch_read_markers (
    user_id BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    root_id BIGINT NOT NULL REFERENCES chat_messages (id) ON DELETE CASCADE,
    last_read_message_id BIGINT NOT NULL,
    PRIMARY KEY (user_id, root_id)
);
