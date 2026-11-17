-- Where each photo was taken, from the GPS position in its EXIF data, so the
-- Locations view can place the library on a map without opening every file
-- (#3557). Like taken_at it lives on the one row per library photo, and is
-- read in the same EXIF pass: taken_checked now says the date and the
-- position were both read. A photo with no position, or a 0,0 one, keeps
-- NULL in both columns and is never placed.
ALTER TABLE photo_hashes ADD COLUMN latitude DOUBLE PRECISION;
ALTER TABLE photo_hashes ADD COLUMN longitude DOUBLE PRECISION;

-- Every EXIF read before this one looked only at the date, so every photo is
-- read again for its position. The dates already stored stay.
UPDATE photo_hashes SET taken_checked = FALSE;
