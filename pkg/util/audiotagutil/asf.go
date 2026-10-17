package audiotagutil

import (
	"bytes"
	"encoding/binary"
	"io"
	"math"
	"strconv"
	"strings"
	"time"
	"unicode/utf16"
)

// ASF header objects this package reads.
var (
	asfFileProperties      = []byte{0xA1, 0xDC, 0xAB, 0x8C, 0x47, 0xA9, 0xCF, 0x11, 0x8E, 0xE4, 0x00, 0xC0, 0x0C, 0x20, 0x53, 0x65}
	asfContentDescription  = []byte{0x33, 0x26, 0xB2, 0x75, 0x8E, 0x66, 0xCF, 0x11, 0xA6, 0xD9, 0x00, 0xAA, 0x00, 0x62, 0xCE, 0x6C}
	asfExtendedDescription = []byte{0x40, 0xA4, 0xD0, 0xD2, 0x07, 0xE3, 0xD2, 0x11, 0x97, 0xF0, 0x00, 0xA0, 0xC9, 0x5E, 0xA8, 0x50}
)

// ASF descriptor value types.
const (
	asfFrontCover = 3 // the WM/Picture type of a front cover

	asfString = 0
	asfBytes  = 1
	asfDWord  = 3
	asfQWord  = 4
	asfWord   = 5
)

// readASF reads a WMA file's header object, which holds every tag and the
// duration and is held to MaxTagBytes, into memory and walks its objects.
func readASF(src io.ReaderAt, size int64) (parsed, error) {
	head := make([]byte, 30)
	if err := readFull(src, 0, head); err != nil {
		return parsed{}, ErrMalformed
	}
	n := binary.LittleEndian.Uint64(head[16:24])
	if n < 30 || n > MaxTagBytes {
		return parsed{}, ErrTagTooLarge
	}
	header, err := readRegion(src, size, 0, int64(n))
	if err != nil {
		return parsed{}, err
	}
	var found parsed
	for b, count := header[30:], 0; len(b) >= 24 && count < maxBoxes; count++ {
		objLen := binary.LittleEndian.Uint64(b[16:24])
		if objLen < 24 || objLen > uint64(len(b)) {
			return parsed{}, ErrTagTooLarge
		}
		obj := b[:objLen]
		switch {
		case bytes.Equal(obj[:16], asfFileProperties):
			found.tags.Duration, found.tags.DurationExact = asfDuration(obj)
		case bytes.Equal(obj[:16], asfContentDescription):
			if err := asfContentTags(obj[24:], &found.tags); err != nil {
				return parsed{}, err
			}
		case bytes.Equal(obj[:16], asfExtendedDescription):
			if err := asfExtendedTags(obj[24:], &found); err != nil {
				return parsed{}, err
			}
		}
		b = b[objLen:]
	}
	return found, nil
}

// asfDuration is the File Properties play duration (100 ns units) less the
// preroll (ms). A broadcast file's durations are not valid.
func asfDuration(obj []byte) (time.Duration, bool) {
	if len(obj) < 104 || binary.LittleEndian.Uint32(obj[88:92])&1 != 0 {
		return 0, false
	}
	play := binary.LittleEndian.Uint64(obj[64:72])
	preroll := binary.LittleEndian.Uint64(obj[80:88])
	if play > math.MaxInt64/100 || preroll > math.MaxInt64/uint64(time.Millisecond) {
		return 0, false
	}
	d := time.Duration(play)*100 - time.Duration(preroll)*time.Millisecond
	return d, d > 0
}

// asfContentTags reads the Content Description object: five lengths, then
// title, author, copyright, description and rating as UTF-16LE.
func asfContentTags(b []byte, t *Tags) error {
	if len(b) < 10 {
		return ErrMalformed
	}
	fields := make([][]byte, 5)
	rest := b[10:]
	for i := range fields {
		l := int(binary.LittleEndian.Uint16(b[2*i:]))
		if l > len(rest) {
			return ErrTagTooLarge
		}
		fields[i], rest = rest[:l], rest[l:]
	}
	t.Title, t.Artist = utf16Text(fields[0]), utf16Text(fields[1])
	return nil
}

// asfExtendedTags reads the Extended Content Description object's named
// descriptors, WM/Picture among them.
func asfExtendedTags(b []byte, found *parsed) error {
	if len(b) < 2 {
		return ErrMalformed
	}
	count := int(binary.LittleEndian.Uint16(b))
	b = b[2:]
	zeroBasedTrack := -1
	for range count {
		if len(b) < 2 {
			return ErrMalformed
		}
		nameLen := int(binary.LittleEndian.Uint16(b))
		if 2+nameLen+4 > len(b) {
			return ErrTagTooLarge
		}
		name := utf16Text(b[2 : 2+nameLen])
		b = b[2+nameLen:]
		kind := binary.LittleEndian.Uint16(b)
		valueLen := int(binary.LittleEndian.Uint16(b[2:]))
		if 4+valueLen > len(b) {
			return ErrTagTooLarge
		}
		value := b[4 : 4+valueLen]
		b = b[4+valueLen:]
		t := &found.tags
		switch name {
		case "WM/AlbumTitle":
			t.Album = asfText(kind, value)
		case "WM/AlbumArtist":
			t.AlbumArtist = asfText(kind, value)
		case "WM/Genre":
			t.Genre = asfText(kind, value)
		case "WM/Year":
			t.Year = clampYear(leadingInt(asfText(kind, value)))
		case "WM/TrackNumber":
			t.TrackNo = clampCount(leadingInt(asfText(kind, value)))
		case "WM/Track":
			zeroBasedTrack = leadingInt(asfText(kind, value))
		case "WM/PartOfSet":
			t.DiscNo = clampCount(leadingInt(asfText(kind, value)))
		case "WM/Picture":
			if kind != asfBytes {
				break
			}
			p, front, err := asfPicture(value)
			if err != nil {
				return err
			}
			if p != nil && (found.picture == nil || front) {
				found.picture = p
			}
		}
	}
	if found.tags.TrackNo == 0 && zeroBasedTrack >= 0 {
		found.tags.TrackNo = clampCount(zeroBasedTrack + 1)
	}
	return nil
}

// asfText renders a descriptor value as text, whatever its type.
func asfText(kind uint16, v []byte) string {
	switch {
	case kind == asfString:
		return utf16Text(v)
	case kind == asfDWord && len(v) >= 4:
		return strconv.FormatUint(uint64(binary.LittleEndian.Uint32(v)), 10)
	case kind == asfQWord && len(v) >= 8:
		return strconv.FormatUint(binary.LittleEndian.Uint64(v), 10)
	case kind == asfWord && len(v) >= 2:
		return strconv.FormatUint(uint64(binary.LittleEndian.Uint16(v)), 10)
	}
	return ""
}

// asfPicture reads a WM/Picture value: picture type, data length, MIME type
// and description as NUL-terminated UTF-16LE, then the data.
func asfPicture(v []byte) (*picture, bool, error) {
	if len(v) < 5 {
		return nil, false, ErrMalformed
	}
	front := v[0] == asfFrontCover
	dataLen := uint64(binary.LittleEndian.Uint32(v[1:5]))
	rest := v[5:]
	var mime string
	for i := range 2 { // the MIME type, then the description
		end := utf16Terminator(rest)
		if end < 0 {
			return nil, false, ErrMalformed
		}
		if i == 0 {
			mime = utf16Text(rest[:end])
		}
		rest = rest[end+2:]
	}
	if dataLen > uint64(len(rest)) {
		return nil, false, ErrTagTooLarge
	}
	if dataLen == 0 {
		return nil, false, nil
	}
	return newPicture(mime, rest[:dataLen]), front, nil
}

// utf16Terminator is the offset of the first aligned UTF-16 NUL in b, or -1.
func utf16Terminator(b []byte) int {
	for i := 0; i+1 < len(b); i += 2 {
		if b[i] == 0 && b[i+1] == 0 {
			return i
		}
	}
	return -1
}

// utf16Text decodes UTF-16LE, dropping an odd trailing byte.
func utf16Text(b []byte) string {
	if len(b) > 8*maxTextBytes {
		b = b[:8*maxTextBytes]
	}
	u := make([]uint16, len(b)/2)
	for i := range u {
		u[i] = binary.LittleEndian.Uint16(b[2*i:])
	}
	return cleanText(strings.ToValidUTF8(string(utf16.Decode(u)), ""))
}
