-- Group names are unique ignoring case (#1910), so "Family" and "family" can't
-- both exist. An index rather than rebuilding groups with COLLATE NOCASE:
-- migrations run in a transaction with foreign keys on, and dropping the old
-- table would cascade-delete every member and grant.
CREATE UNIQUE INDEX idx_groups_name_nocase ON groups (name COLLATE NOCASE);
