// Package audiotagutil reads the tags, the duration and the embedded cover of
// an audio file (mp3, aac, flac, ogg/opus, m4a, wav and wma) without trusting
// any length the file declares.
//
// The tag parsing for mp3, m4a, flac and ogg is github.com/dhowden/tag. That
// library sizes allocations from length fields the file controls, so it never
// sees a file directly: this package first walks the container's own size
// fields, refuses anything above MaxTagBytes or above the file's size, and
// then hands the library only the section it checked, behind a read budget
// and a recover(). Duration, WAV and WMA are read here, from fixed-layout
// headers at known offsets. Nothing reads a whole file: the file is read at
// offsets through io.ReaderAt, which vfs.File satisfies.
package audiotagutil

import (
	"errors"
	"io"
	"time"
)

// MaxTagBytes is the most of a file that is ever read as tag data: an ID3v2
// tag, the FLAC metadata blocks, an MP4 ilst atom, an Ogg comment header, a
// WAV LIST chunk or an ASF header object. A file declaring more is refused
// with ErrTagTooLarge before anything is allocated for it.
const MaxTagBytes = 16 << 20

var (
	// ErrUnsupported is returned for a file that is not one of the audio
	// formats this package reads.
	ErrUnsupported = errors.New("audiotagutil: not a supported audio format")
	// ErrTagTooLarge is returned when a tag declares a length above
	// MaxTagBytes, above the file's size or above the structure holding it.
	ErrTagTooLarge = errors.New("audiotagutil: tag declares more data than allowed")
	// ErrMalformed is returned for a tag that cannot be parsed, including one
	// that made the tag library panic.
	ErrMalformed = errors.New("audiotagutil: malformed tag")
	// ErrNoPicture is returned by ReadPicture for a file with no embedded
	// picture.
	ErrNoPicture = errors.New("audiotagutil: no embedded picture")
)

// ReadParams names the file to read.
type ReadParams struct {
	// File is the audio file, read at offsets and never whole. A vfs.File
	// satisfies it.
	File io.ReaderAt
	// Size is the file's size from Stat. No length the file declares may
	// exceed it.
	Size int64
}

// ReadResult is what Read found.
type ReadResult struct {
	// Tags are the file's tags and duration. Fields the file does not carry
	// are zero.
	Tags Tags
}

// Tags is the metadata of one track.
type Tags struct {
	// Title is the track title.
	Title string
	// Artist is the track artist.
	Artist string
	// AlbumArtist is the album artist, empty when the file does not name one.
	AlbumArtist string
	// Album is the album title.
	Album string
	// Genre is the genre, with ID3's numeric genres expanded.
	Genre string
	// TrackNo is the track number, 0 when absent.
	TrackNo int
	// DiscNo is the disc number, 0 when absent.
	DiscNo int
	// Year is the release year, 0 when absent.
	Year int
	// Duration is the playing time, 0 when it could not be read.
	Duration time.Duration
	// DurationExact is false when Duration is an estimate from the bitrate
	// and the file size, or unknown.
	DurationExact bool
	// Picture describes the embedded cover, nil when there is none. The
	// picture's bytes are hashed and dropped; ReadPicture reads them again.
	Picture *PictureRef
}

// PictureRef identifies an embedded picture without holding its bytes.
type PictureRef struct {
	// MIMEType is the picture's media type, such as image/jpeg.
	MIMEType string
	// Size is the picture's length in bytes.
	Size int64
	// SHA256 is the hex sha256 of the picture's bytes, the same for every
	// track that embeds the same picture.
	SHA256 string
}

// Read returns the tags, duration and embedded-cover reference of an audio
// file. The front cover is preferred when a file embeds several pictures. A
// file with no tags is not an error: its Tags carry only what the container
// says, such as the duration.
func Read(params ReadParams) (ReadResult, error) {
	found, err := read(params.File, params.Size)
	if err != nil {
		return ReadResult{}, err
	}
	tags := found.tags
	if found.picture != nil {
		tags.Picture = pictureRef(found.picture)
	}
	return ReadResult{Tags: tags}, nil
}

// ReadPictureParams names the file whose embedded picture to read.
type ReadPictureParams struct {
	// File is the audio file, read at offsets and never whole. A vfs.File
	// satisfies it.
	File io.ReaderAt
	// Size is the file's size from Stat.
	Size int64
}

// ReadPictureResult is an embedded picture.
type ReadPictureResult struct {
	// MIMEType is the picture's media type, such as image/jpeg.
	MIMEType string
	// Data is the picture's bytes, at most MaxTagBytes long.
	Data []byte
}

// ReadPicture returns the embedded picture that Read describes in
// Tags.Picture, going through the same checks. A file without one is
// ErrNoPicture.
func ReadPicture(params ReadPictureParams) (ReadPictureResult, error) {
	found, err := read(params.File, params.Size)
	if err != nil {
		return ReadPictureResult{}, err
	}
	if found.picture == nil {
		return ReadPictureResult{}, ErrNoPicture
	}
	return ReadPictureResult{MIMEType: found.picture.mimeType, Data: found.picture.data}, nil
}
