-- The identity of this install. A factory reset drops this table with every
-- other and the re-run of this migration issues a new id, which is how an
-- instance that did not serve the reset learns the install it booted on is
-- gone and restarts (#3085). It is in the database, not in a file, so that it
-- changes in the same transaction as the reset.
CREATE TABLE install (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    install_id TEXT NOT NULL
);

INSERT INTO install (id, install_id) VALUES (1, lower(hex(randomblob(16))));
