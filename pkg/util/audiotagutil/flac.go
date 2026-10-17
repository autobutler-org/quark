package audiotagutil

import (
	"encoding/binary"
	"io"
	"time"

	"github.com/dhowden/tag"
)

// FLAC metadata block types this package looks inside.
const (
	flacStreamInfo    = 0
	flacVorbisComment = 4
	flacPicture       = 6
)

// readFLAC walks the metadata blocks after "fLaC", checks every length the
// library would trust, reads the duration from STREAMINFO, and then lets the
// library parse exactly the blocks it walked.
func readFLAC(src io.ReaderAt, size int64) (parsed, error) {
	var dur time.Duration
	var exact bool
	off := int64(4)
	hdr := make([]byte, 4)
	for blocks := 0; ; blocks++ {
		if blocks == maxBoxes || off-4 > MaxTagBytes {
			return parsed{}, ErrTagTooLarge
		}
		if err := readFull(src, off, hdr); err != nil {
			return parsed{}, ErrMalformed
		}
		last := hdr[0]&0x80 != 0
		body := off + 4
		n := int64(hdr[1])<<16 | int64(hdr[2])<<8 | int64(hdr[3])
		if n > size-body {
			return parsed{}, ErrTagTooLarge
		}
		switch hdr[0] & 0x7F {
		case flacStreamInfo:
			if n >= 34 {
				info := make([]byte, 34)
				if err := readFull(src, body, info); err == nil {
					dur, exact = streamInfoDuration(info)
				}
			}
		case flacVorbisComment:
			if err := checkVorbisComment(io.NewSectionReader(src, body, n), n); err != nil {
				return parsed{}, err
			}
		case flacPicture:
			if err := checkPictureBlock(io.NewSectionReader(src, body, n), n); err != nil {
				return parsed{}, err
			}
		}
		off = body + n
		if last {
			break
		}
	}
	if off-4 > MaxTagBytes {
		return parsed{}, ErrTagTooLarge
	}
	found, err := libraryTags(src, 0, off, tag.ReadFLACTags)
	if err != nil {
		return parsed{}, err
	}
	found.tags.Duration, found.tags.DurationExact = dur, exact
	return found, nil
}

// streamInfoDuration is the total sample count over the sample rate, both in
// the 34-byte STREAMINFO block. A count of 0 means the encoder did not know.
func streamInfoDuration(info []byte) (time.Duration, bool) {
	rate := uint64(info[10])<<12 | uint64(info[11])<<4 | uint64(info[12])>>4
	samples := uint64(info[13]&0x0F)<<32 | uint64(binary.BigEndian.Uint32(info[14:18]))
	return samplesDuration(samples, rate)
}
