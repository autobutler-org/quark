package audiotagutil

import (
	"bytes"
	"errors"
	"io"
	"runtime"
	"testing"
	"time"
)

const gib = 1 << 30

// TestHostileLengthsFailWithoutAllocating declares a gibibyte (or the most the
// field can hold) in every length field the readers trust, inside a file of a
// few hundred bytes. Each must fail, and the read must allocate a few
// megabytes at most, never the declared length. #116 upstream is the FLAC
// picture case: the library makes the picture's declared length before
// reading it.
func TestHostileLengthsFailWithoutAllocating(t *testing.T) {
	hugePicture := pictureBlock(3, "image/jpeg", gib, fakeJPEG(1))
	hugeComment := cat(le32(4), []byte("test"), le32(1), le32(gib), []byte("TITLE=x"))
	cases := map[string][]byte{
		"flac picture data length":     flacFile(1, 1, flacBlock(6, false, hugePicture)),
		"flac block longer than file":  cat([]byte("fLaC"), []byte{0x84, 0xFF, 0xFF, 0xFF}, vorbisComment("TITLE=x")),
		"flac vorbis comment length":   flacFile(1, 1, flacBlock(4, false, hugeComment)),
		"flac base64 picture length":   flacFile(1, 1, flacBlock(4, false, vorbisComment(pictureComment(hugePicture)))),
		"ogg vorbis comment length":    cat(oggPage(1, 0, 2, 0, vorbisID(44100)), oggPage(1, 1, 0, 0, cat([]byte("\x03vorbis"), hugeComment))),
		"opus base64 picture length":   opusFile(0, 48000, pictureComment(hugePicture)),
		"id3v2 tag size":               cat([]byte("ID3\x03\x00\x00"), syncsafe(1<<28-1), id3Text("TIT2", "x").data, mp3Frames(2, 0)),
		"m4a moov longer than file":    cat(atom("ftyp", []byte("M4A "), be32(0)), be32(gib), []byte("moov"), mvhd(1000, 1000)),
		"m4a ilst longer than meta":    m4aWithIlstHeader(be32(gib)),
		"m4a ilst item longer than it": m4aFile(1000, 1000, cat(be32(gib), []byte("covr"), dataAtom(13, fakeJPEG(2)))),
		"wav LIST chunk":               wavFile(wavFmt(1000), cat([]byte("LIST"), le32(gib), []byte("INFO"))),
		"wav id3 chunk":                wavFile(wavFmt(1000), riffChunk("id3 ", cat([]byte("ID3\x03\x00\x00"), syncsafe(1<<28-1), make([]byte, 20)))),
		"asf header object":            cat(asfHeaderGUID, le64(gib), le32(0), []byte{1, 2}, make([]byte, 64)),
		"asf child object":             asfFile(cat(asfContentDescription, le64(gib), make([]byte, 10))),
		"asf picture data length":      asfFile(asfExtended(asfDescriptor{"WM/Picture", asfBytes, cat([]byte{3}, le32(gib), utf16z("image/jpeg"), utf16z(""), fakeJPEG(3))})),
	}
	// An ID3 frame whose size field claims a gibibyte inside a tag that is
	// honest about its own size: the library reads only the checked section.
	frame := cat([]byte("TIT2"), be32(gib), []byte{0, 0}, []byte{0, 'x'})
	cases["id3v2 frame size"] = cat([]byte("ID3\x03\x00\x00"), syncsafe(len(frame)), frame, mp3Frames(2, 0))

	for name, f := range cases {
		t.Run(name, func(t *testing.T) {
			var before, after runtime.MemStats
			runtime.GC()
			runtime.ReadMemStats(&before)
			_, err := Read(ReadParams{File: bytes.NewReader(f), Size: int64(len(f))})
			runtime.ReadMemStats(&after)
			if !errors.Is(err, ErrTagTooLarge) && !errors.Is(err, ErrMalformed) {
				t.Errorf("Read = %v, want ErrTagTooLarge or ErrMalformed", err)
			}
			if allocated := after.TotalAlloc - before.TotalAlloc; allocated > 4<<20 {
				t.Errorf("Read allocated %d bytes for a %d-byte file", allocated, len(f))
			}
		})
	}
}

func m4aWithIlstHeader(header []byte) []byte {
	ilst := cat(header, []byte("ilst"), textItem("\xa9nam", "x"))
	meta := atom("meta", be32(0), ilst)
	return cat(atom("ftyp", []byte("M4A "), be32(0)), atom("moov", mvhd(1000, 1000), atom("udta", meta)))
}

func TestTagLargerThanMaxTagBytesIsRefused(t *testing.T) {
	// A 17 MiB picture in a FLAC file that really holds it.
	big := make([]byte, MaxTagBytes+1<<20)
	f := flacFile(1, 1, flacBlock(6, false, picture3("image/jpeg", big)))
	if _, err := Read(ReadParams{File: bytes.NewReader(f), Size: int64(len(f))}); !errors.Is(err, ErrTagTooLarge) {
		t.Errorf("Read = %v, want ErrTagTooLarge", err)
	}
}

// sparseFile is a large file that is a prefix and a suffix around zeros. It
// counts the bytes read from it, to show a read costs kilobytes of a 4 GiB
// file.
type sparseFile struct {
	prefix, suffix []byte
	size           int64
	read           int64
}

func (s *sparseFile) ReadAt(p []byte, off int64) (int, error) {
	if off >= s.size {
		return 0, io.EOF
	}
	n := len(p)
	if rem := s.size - off; int64(n) > rem {
		n = int(rem)
	}
	clear(p[:n])
	for i := range n {
		pos := off + int64(i)
		switch {
		case pos < int64(len(s.prefix)):
			p[i] = s.prefix[pos]
		case pos >= s.size-int64(len(s.suffix)):
			p[i] = s.suffix[pos-(s.size-int64(len(s.suffix)))]
		}
	}
	s.read += int64(n)
	if n < len(p) {
		return n, io.EOF
	}
	return n, nil
}

func TestReadCostsKilobytesOfAHugeFile(t *testing.T) {
	const size = 4 * gib
	moov := atom("moov", mvhd(1000, 7000), atom("udta", atom("meta", be32(0), atom("ilst", textItem("\xa9nam", "Long")))))
	ftyp := atom("ftyp", []byte("M4A "), be32(0), []byte("M4A "))
	mdatLen := uint64(size - len(ftyp) - len(moov))
	cases := map[string]*sparseFile{
		"mp3":  {prefix: cat(id3v23(id3Text("TIT2", "Long")), mp3Frames(3, 0))},
		"flac": {prefix: flacFile(44100*3600, 44100, flacBlock(4, false, vorbisComment("TITLE=Long")))},
		"m4a with moov last": {
			prefix: cat(ftyp, be32(1), []byte("mdat"), binaryBE64(mdatLen)),
			suffix: moov,
		},
		"wav": {prefix: cat([]byte("RIFF"), le32(size-8), []byte("WAVE"), wavFmt(176400),
			riffChunk("LIST", cat([]byte("INFO"), riffChunk("INAM", []byte("Long\x00")))), []byte("data"), le32(0xFFFFFFF0))},
		"ogg": {
			prefix: cat(oggPage(5, 0, 2, 0, vorbisID(44100)), oggPage(5, 1, 0, 0, cat([]byte("\x03vorbis"), vorbisComment("TITLE=Long"), []byte{1}))),
			suffix: oggPage(5, 99, 4, 44100*7200, make([]byte, 100)),
		},
	}
	for name, f := range cases {
		t.Run(name, func(t *testing.T) {
			f.size = size
			res, err := Read(ReadParams{File: f, Size: f.size})
			if err != nil {
				t.Fatalf("Read: %v", err)
			}
			if res.Tags.Title != "Long" || res.Tags.Duration < time.Second {
				t.Errorf("tags = %+v", res.Tags)
			}
			if f.read > 512<<10 {
				t.Errorf("read %d bytes of a %d-byte file", f.read, f.size)
			}
		})
	}
}

func binaryBE64(n uint64) []byte {
	return cat(be32(uint32(n>>32)), be32(uint32(n)))
}
