-- Only the index is dropped. The renames the up migration made ('/' replaced,
-- duplicates suffixed) are not reversed: the original names are gone.
DROP INDEX IF EXISTS idx_photo_albums_sibling_name;
