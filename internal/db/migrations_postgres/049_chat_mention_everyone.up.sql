-- The PostgreSQL half of 049_chat_mention_everyone. mention_everyone (256)
-- joins the Moderator and Owner presets (#4293). Sets are stored expanded,
-- so every row holding all of Moderator's earlier bits (239: read, send,
-- react, delete, manage_members, manage_reactions, attach_files) gains it and
-- keeps matching its preset.
UPDATE chat_channel_members SET permissions = permissions | 256 WHERE permissions & 239 = 239;
