package audiotagutil

import (
	"encoding/binary"
	"io"
	"math"
	"time"

	"github.com/dhowden/tag"
)

// readMP4 finds the moov atom, checks the atoms holding the tags
// (moov/udta/meta/ilst), reads the duration from mvhd, and gives the library
// moov alone. moov itself may be large (an audiobook's sample tables), but the
// library seeks past everything except the tag atoms, and ilst is held to
// MaxTagBytes.
func readMP4(src io.ReaderAt, size int64) (parsed, error) {
	var moov *mp4Box
	err := walkMP4(src, 0, size, func(b mp4Box) error {
		if b.name == "moov" && moov == nil {
			moov = &b
		}
		return nil
	})
	if err != nil {
		return parsed{}, err
	}
	if moov == nil {
		return parsed{}, nil
	}
	var dur time.Duration
	var exact bool
	err = walkMP4(src, moov.off+moov.hdr, moov.off+moov.n, func(b mp4Box) error {
		switch b.name {
		case "mvhd":
			dur, exact = mvhdDuration(src, b)
		case "udta":
			return checkMP4Tags(src, b)
		}
		return nil
	})
	if err != nil {
		return parsed{}, err
	}
	found, err := libraryTags(src, moov.off, moov.n, tag.ReadAtoms)
	if err != nil {
		return parsed{}, err
	}
	found.tags.Duration, found.tags.DurationExact = dur, exact
	return found, nil
}

// checkMP4Tags walks udta down to ilst, so every atom the library reads data
// from sits inside its parent, and holds ilst to MaxTagBytes.
func checkMP4Tags(src io.ReaderAt, udta mp4Box) error {
	return walkMP4(src, udta.off+udta.hdr, udta.off+udta.n, func(meta mp4Box) error {
		if meta.name != "meta" {
			return nil
		}
		// meta is a full box: four bytes of version and flags before its children.
		return walkMP4(src, meta.off+meta.hdr+4, meta.off+meta.n, func(ilst mp4Box) error {
			if ilst.name != "ilst" {
				return nil
			}
			if ilst.n > MaxTagBytes {
				return ErrTagTooLarge
			}
			return walkMP4(src, ilst.off+ilst.hdr, ilst.off+ilst.n, func(mp4Box) error { return nil })
		})
	})
}

// walkMP4 calls fn for each atom between start and end, refusing an atom that
// claims to run past end.
func walkMP4(src io.ReaderAt, start, end int64, fn func(mp4Box) error) error {
	hdr := make([]byte, 16)
	for off, count := start, 0; off+8 <= end; count++ {
		if count == maxBoxes {
			return ErrMalformed
		}
		if readFull(src, off, hdr[:8]) != nil {
			return ErrMalformed
		}
		b := mp4Box{name: string(hdr[4:8]), off: off, hdr: 8, n: int64(binary.BigEndian.Uint32(hdr[:4]))}
		switch b.n {
		case 0: // runs to the end of its parent
			b.n = end - off
		case 1: // a 64-bit size follows the type
			if readFull(src, off+8, hdr[8:16]) != nil {
				return ErrMalformed
			}
			large := binary.BigEndian.Uint64(hdr[8:16])
			if large > math.MaxInt64 {
				return ErrTagTooLarge
			}
			b.n, b.hdr = int64(large), 16
		}
		if b.n < b.hdr || b.n > end-off {
			return ErrTagTooLarge
		}
		if err := fn(b); err != nil {
			return err
		}
		off += b.n
	}
	return nil
}

// mvhdDuration is the movie header's duration over its timescale.
func mvhdDuration(src io.ReaderAt, b mp4Box) (time.Duration, bool) {
	body := make([]byte, 32)
	if b.n-b.hdr < 20 || readFull(src, b.off+b.hdr, body[:min(int64(len(body)), b.n-b.hdr)]) != nil {
		return 0, false
	}
	var scale, units uint64
	if body[0] == 1 {
		if b.n-b.hdr < 32 {
			return 0, false
		}
		scale, units = uint64(binary.BigEndian.Uint32(body[20:24])), binary.BigEndian.Uint64(body[24:32])
	} else {
		scale, units = uint64(binary.BigEndian.Uint32(body[12:16])), uint64(binary.BigEndian.Uint32(body[16:20]))
		if units == math.MaxUint32 {
			return 0, false
		}
	}
	if units == math.MaxUint64 {
		return 0, false
	}
	return samplesDuration(units, scale)
}
