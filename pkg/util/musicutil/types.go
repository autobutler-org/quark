package musicutil

// folderCovers remembers the cover found for the last folder looked at, so a
// backfill walking an album lists and hashes its cover.jpg once rather than
// once per track. The walk visits a folder's files together, so one entry is
// enough.
type folderCovers struct {
	folder string
	found  bool
	cover  folderCover
}

// folderCover is a folder image chosen as cover art.
type folderCover struct {
	// name is the image's file name, stored as cover_source "folder:<name>".
	name string
	// key is the hex sha256 of its bytes; "" when no folder image qualifies.
	key string
}

// scanState is a stored row's unchanged-file check.
type scanState struct {
	size, mtime, version int64
}

// albumGroup accumulates one album from the rows a caller can read.
type albumGroup struct {
	album Album
	cover coverPick
}

// artistGroup accumulates one album artist from the rows a caller can read.
type artistGroup struct {
	artist Artist
	albums map[string]struct{}
	cover  coverPick
}

// coverPick is the track whose cover stands for a group: one with cover art
// first, then the lowest path, then the lowest serial. It is the order the
// admin's SQL aggregate uses.
type coverPick struct {
	set      bool
	hasCover bool
	serial   string
	relPath  string
}
