-- An anonymous channel (#2949) shows its members to each other under a
-- pseudonym, never their account. anonymous is set when the channel is made
-- and never changes, so nothing a member wrote under their account is ever
-- served under a pseudonym, or the other way round. A direct message is never
-- anonymous.
--
-- chat_channel_pseudonyms is the per-channel pseudonym of each account that
-- appears in an anonymous channel, made the first time it is needed.
-- pseudonym_id is random and negative, so it never names an account, and it
-- never changes: reactions, poll answers, key grants and channel events bind
-- it in place of the account id. alias is the name the members see, which a
-- holder of manage_members or an admin may change, unique in the channel
-- whatever its case. box_public_key and sign_public_key are the X25519 and
-- Ed25519 keys the account's app derived for this channel alone and
-- published, so nothing it seals or signs there matches its account keys.
-- They stay NULL until the app publishes them, and are cleared when the
-- account's chat identity changes.
ALTER TABLE chat_channels ADD COLUMN anonymous INTEGER NOT NULL DEFAULT 0;

CREATE TABLE chat_channel_pseudonyms (
    channel_id   INTEGER NOT NULL REFERENCES chat_channels (id) ON DELETE CASCADE,
    user_id      INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    pseudonym_id INTEGER NOT NULL CHECK (pseudonym_id < 0),
    alias        TEXT NOT NULL,
    box_public_key  BLOB,
    sign_public_key BLOB,
    PRIMARY KEY (channel_id, user_id),
    UNIQUE (channel_id, pseudonym_id),
    UNIQUE (channel_id, alias COLLATE NOCASE)
);
