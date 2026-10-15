package audiotagutil

import (
	"bytes"
	"encoding/binary"
	"io"
	"time"

	"github.com/dhowden/tag"
)

// oggMaxPage is the longest an Ogg page can be: a 27-byte header, 255
// segment sizes and 255 segments of 255 bytes.
const oggMaxPage = 27 + 255 + 255*255

var (
	vorbisIDPrefix      = []byte("\x01vorbis")
	vorbisCommentPrefix = []byte("\x03vorbis")
	opusHeadPrefix      = []byte("OpusHead")
	opusTagsPrefix      = []byte("OpusTags")
	oggFLACPrefix       = []byte{0x7F, 'F', 'L', 'A', 'C'}
)

// readOgg reassembles packets from the first pages the way the tag library
// does, every logical stream at once, until it reaches the comment header the
// library will parse. That header is checked, and the library is then given
// only the pages read so far. The first packet of the first stream gives the
// sample rate; the last page of that stream gives the sample count.
func readOgg(src io.ReaderAt, size int64) (parsed, error) {
	var idPacket []byte
	var firstSerial uint32
	packets := map[uint32][]byte{}
	hdr := make([]byte, 27)
	segments := make([]byte, 255)
	body := make([]byte, 255*255)
	off := int64(0)
	comment := false
	for !comment {
		if off > MaxTagBytes {
			return parsed{}, ErrTagTooLarge
		}
		if readFull(src, off, hdr) != nil || string(hdr[:4]) != "OggS" {
			break
		}
		serial := binary.LittleEndian.Uint32(hdr[14:18])
		if off == 0 {
			firstSerial = serial
		}
		seg := segments[:hdr[26]]
		if readFull(src, off+27, seg) != nil {
			break
		}
		bodyLen := 0
		for _, s := range seg {
			bodyLen += int(s)
		}
		data := body[:bodyLen]
		if readFull(src, off+27+int64(len(seg)), data) != nil {
			break
		}
		off += 27 + int64(len(seg)) + int64(bodyLen)
		pkt, ok := packets[serial]
		if hdr[5]&1 == 0 {
			pkt = nil
		} else if !ok {
			return parsed{}, ErrMalformed // the library refuses a continuation of nothing
		}
		p := 0
		for _, s := range seg {
			pkt = append(pkt, data[p:p+int(s)]...)
			p += int(s)
			if s == 255 {
				continue
			}
			if idPacket == nil && serial == firstSerial {
				idPacket = pkt[:min(len(pkt), 64):min(len(pkt), 64)]
			}
			if prefix := commentPrefix(pkt); prefix != nil {
				if err := checkVorbisComment(bytes.NewReader(pkt[len(prefix):]), int64(len(pkt)-len(prefix))); err != nil {
					return parsed{}, err
				}
				comment = true
				break
			}
			pkt = nil
		}
		packets[serial] = pkt
	}
	var found parsed
	if comment {
		var err error
		if found, err = libraryTags(src, 0, off, func(r io.ReadSeeker) (tag.Metadata, error) { return tag.ReadOGGTags(r) }); err != nil {
			return parsed{}, err
		}
	}
	found.tags.Duration, found.tags.DurationExact = oggDuration(src, size, firstSerial, idPacket)
	return found, nil
}

func commentPrefix(pkt []byte) []byte {
	for _, prefix := range [][]byte{vorbisCommentPrefix, opusTagsPrefix} {
		if bytes.HasPrefix(pkt, prefix) {
			return prefix
		}
	}
	return nil
}

// oggDuration is the granule position of the stream's last page, less Opus's
// pre-skip, over the rate its identification header names.
func oggDuration(src io.ReaderAt, size int64, serial uint32, id []byte) (time.Duration, bool) {
	var rate, skip uint64
	switch {
	case bytes.HasPrefix(id, vorbisIDPrefix) && len(id) >= 16:
		rate = uint64(binary.LittleEndian.Uint32(id[12:16]))
	case bytes.HasPrefix(id, opusHeadPrefix) && len(id) >= 12:
		rate, skip = 48000, uint64(binary.LittleEndian.Uint16(id[10:12]))
	case bytes.HasPrefix(id, oggFLACPrefix) && len(id) >= 17+34:
		rate = uint64(id[27])<<12 | uint64(id[28])<<4 | uint64(id[29])>>4
	}
	if rate == 0 {
		return 0, false
	}
	granule, ok := lastGranule(src, size, serial)
	if !ok || granule <= skip {
		return 0, false
	}
	return samplesDuration(granule-skip, rate)
}

// lastGranule finds the last page of the stream in the file's final
// oggMaxPage bytes, the furthest back a last page can start.
func lastGranule(src io.ReaderAt, size int64, serial uint32) (uint64, bool) {
	n := min(size, oggMaxPage)
	tail := make([]byte, n)
	if readFull(src, size-n, tail) != nil {
		return 0, false
	}
	for i := len(tail) - 27; i >= 0; i-- {
		if string(tail[i:i+4]) != "OggS" || tail[i+4] != 0 || binary.LittleEndian.Uint32(tail[i+14:i+18]) != serial {
			continue
		}
		if g := binary.LittleEndian.Uint64(tail[i+6 : i+14]); g != ^uint64(0) {
			return g, true
		}
	}
	return 0, false
}
