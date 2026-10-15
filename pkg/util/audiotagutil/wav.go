package audiotagutil

import (
	"encoding/binary"
	"io"

	"github.com/dhowden/tag"
)

// readWAV walks the RIFF chunks: fmt gives the byte rate, data the length of
// the audio, LIST/INFO the tags, and an "id3 " chunk an ID3v2 tag, which wins
// over INFO field by field.
func readWAV(src io.ReaderAt, size int64) (parsed, error) {
	head := make([]byte, 8)
	if err := readFull(src, 4, head[:4]); err != nil {
		return parsed{}, ErrMalformed
	}
	// Streaming writers leave the RIFF size at 0 or 0xFFFFFFFF; trust only a
	// size that fits the file.
	end := 8 + int64(binary.LittleEndian.Uint32(head[:4]))
	if end < 12 || end > size {
		end = size
	}
	var info, id3 parsed
	var byteRate uint32
	dataLen := int64(-1)
	exact := true
	for off, count := int64(12), 0; off+8 <= end && count < maxBoxes; count++ {
		if readFull(src, off, head) != nil {
			break
		}
		id := string(head[:4])
		body := off + 8
		n := int64(binary.LittleEndian.Uint32(head[4:8]))
		if id == "data" && n > end-body {
			// Streamed writers leave the size at 0 or 0xFFFFFFFF.
			n, exact = end-body, false
		}
		if n > end-body {
			if id == "LIST" || id == "id3 " || id == "ID3 " {
				return parsed{}, ErrTagTooLarge
			}
			break
		}
		switch id {
		case "fmt ":
			if n >= 16 {
				fmtChunk := make([]byte, 16)
				if readFull(src, body, fmtChunk) == nil {
					byteRate = binary.LittleEndian.Uint32(fmtChunk[8:12])
				}
			}
		case "data":
			dataLen = n
		case "LIST":
			list, err := readRegion(src, size, body, n)
			if err != nil {
				return parsed{}, err
			}
			if len(list) >= 4 && string(list[:4]) == "INFO" {
				info.tags = mergeTags(info.tags, riffInfoTags(list[4:]))
			}
		case "id3 ", "ID3 ":
			if n < 10 {
				break
			}
			h := make([]byte, 10)
			if readFull(src, body, h) != nil || string(h[:3]) != "ID3" {
				break
			}
			if tagLen := id3v2Len(h); tagLen > n || tagLen > MaxTagBytes {
				return parsed{}, ErrTagTooLarge
			}
			var err error
			if id3, err = libraryTags(src, body, n, tag.ReadID3v2Tags); err != nil {
				return parsed{}, err
			}
		}
		off = body + n + n&1
	}
	found := parsed{tags: mergeTags(info.tags, id3.tags), picture: id3.picture}
	if dataLen > 0 && byteRate > 0 {
		var ok bool
		if found.tags.Duration, ok = samplesDuration(uint64(dataLen), uint64(byteRate)); ok {
			found.tags.DurationExact = exact
		}
	}
	return found, nil
}

// riffInfoTags reads the INFO subchunks a tagger writes: INAM title, IART
// artist, IPRD album, IGNR genre, ICRD date, and ITRK or IPRT track.
func riffInfoTags(b []byte) Tags {
	var t Tags
	for len(b) >= 8 {
		id := string(b[:4])
		n := int(binary.LittleEndian.Uint32(b[4:8]))
		b = b[8:]
		if n > len(b) {
			break
		}
		v := b[:n]
		switch id {
		case "INAM":
			t.Title = latin1OrUTF8(v)
		case "IART":
			t.Artist = latin1OrUTF8(v)
		case "IPRD":
			t.Album = latin1OrUTF8(v)
		case "IGNR":
			t.Genre = latin1OrUTF8(v)
		case "ICRD":
			t.Year = clampYear(leadingInt(latin1OrUTF8(v)))
		case "ITRK", "IPRT":
			t.TrackNo = clampCount(leadingInt(latin1OrUTF8(v)))
		}
		b = b[min(n+n&1, len(b)):]
	}
	return t
}
