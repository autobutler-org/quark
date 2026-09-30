-- When each photo was taken, from its EXIF data, so the photo grid can sort
-- and group by it without opening every file on every listing (#2592). It
-- lives beside the hashes because photo_hashes is already the one row per
-- library photo, written as the photo is read and dropped when it is deleted
-- or moved. taken_checked says the EXIF was read: a photo with no capture
-- date keeps a NULL taken_at and is not read again.
ALTER TABLE photo_hashes ADD COLUMN taken_at DATETIME;
ALTER TABLE photo_hashes ADD COLUMN taken_checked BOOLEAN NOT NULL DEFAULT 0;
