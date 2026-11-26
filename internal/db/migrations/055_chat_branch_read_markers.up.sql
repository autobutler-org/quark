-- Side conversation read markers (#4349): how far each account has read in
-- each branch, named by its root message. Like chat_read_markers, the Quark
-- counts what is unread from message ids alone, and a marker goes with its
-- account and with its root, which goes with its channel.
CREATE TABLE chat_branch_read_markers (
    user_id              INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    root_id              INTEGER NOT NULL REFERENCES chat_messages (id) ON DELETE CASCADE,
    last_read_message_id INTEGER NOT NULL,
    PRIMARY KEY (user_id, root_id)
);
