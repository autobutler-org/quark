-- Feed subscriptions (#3714). One row is one account's subscription. Nothing
-- is shared: two accounts that follow the same feed each have their own row,
-- so a later unread count has one owner. Deleting the account deletes its
-- feeds and their entries.
--
-- url is the feed address. It can carry a private token, so it is a
-- credential: callers refuse a private, loopback or link-local address before
-- anything is fetched, and they never repeat url in an error or an event.
-- title is the publisher's title. name is the account's own label, because
-- the publisher's title is often useless; empty name means the client shows
-- title. folder is the one label the account files the feed under.
--
-- etag, last_modified, last_fetched_at, last_error and consecutive_failures
-- are for the reader that fetches entries. Nothing writes them here.
-- last_error must never contain the feed URL. feed_entries is created now so
-- that reader does not need another migration; no query touches it yet.
CREATE TABLE feeds (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    url TEXT NOT NULL CHECK (length(url) > 0),
    title TEXT NOT NULL DEFAULT '',
    name TEXT NOT NULL DEFAULT '',
    site_link TEXT NOT NULL DEFAULT '',
    icon TEXT NOT NULL DEFAULT '',
    folder TEXT NOT NULL DEFAULT '',
    etag TEXT NOT NULL DEFAULT '',
    last_modified TEXT NOT NULL DEFAULT '',
    last_fetched_at DATETIME,
    last_error TEXT NOT NULL DEFAULT '',
    consecutive_failures INTEGER NOT NULL DEFAULT 0 CHECK (consecutive_failures >= 0),
    created_at DATETIME NOT NULL DEFAULT (datetime('now')),
    updated_at DATETIME NOT NULL DEFAULT (datetime('now')),
    UNIQUE (user_id, url)
);

-- One stored item of a feed. guid is the item's identity within the feed.
CREATE TABLE feed_entries (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    feed_id INTEGER NOT NULL REFERENCES feeds (id) ON DELETE CASCADE,
    guid TEXT NOT NULL CHECK (length(guid) > 0),
    url TEXT NOT NULL DEFAULT '',
    title TEXT NOT NULL DEFAULT '',
    author TEXT NOT NULL DEFAULT '',
    published_at DATETIME,
    fetched_at DATETIME NOT NULL DEFAULT (datetime('now')),
    content TEXT NOT NULL DEFAULT '',
    content_hash TEXT NOT NULL DEFAULT '',
    UNIQUE (feed_id, guid)
);
