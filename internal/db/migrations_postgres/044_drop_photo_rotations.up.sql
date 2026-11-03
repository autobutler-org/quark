-- A photo's rotation now lives in the file, as its EXIF Orientation tag (#1014),
-- so it moves with the file. Existing rows are dropped, not backfilled.
DROP TABLE IF EXISTS photo_rotations;
