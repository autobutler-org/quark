package audiotagutil

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"testing"
	"time"
)

func readBytes(t *testing.T, b []byte) Tags {
	t.Helper()
	res, err := Read(ReadParams{File: bytes.NewReader(b), Size: int64(len(b))})
	if err != nil {
		t.Fatalf("Read: %v", err)
	}
	return res.Tags
}

func sha(b []byte) string {
	sum := sha256.Sum256(b)
	return hex.EncodeToString(sum[:])
}

func wantDuration(t *testing.T, tags Tags, want time.Duration, exact bool) {
	t.Helper()
	if tags.DurationExact != exact {
		t.Errorf("DurationExact = %v, want %v", tags.DurationExact, exact)
	}
	if diff := tags.Duration - want; diff < -time.Millisecond || diff > time.Millisecond {
		t.Errorf("Duration = %v, want %v", tags.Duration, want)
	}
}

func wantPicture(t *testing.T, tags Tags, mime string, data []byte) {
	t.Helper()
	p := tags.Picture
	if p == nil {
		t.Fatal("Picture = nil, want one")
	}
	if p.MIMEType != mime || p.Size != int64(len(data)) || p.SHA256 != sha(data) {
		t.Errorf("Picture = %+v, want %s, %d bytes, %s", *p, mime, len(data), sha(data))
	}
}

func TestReadMP3(t *testing.T) {
	back, front := fakeJPEG(1), fakeJPEG(2)
	tag := id3v23(
		id3Text("TIT2", "Song"), id3Text("TPE1", "Artist"), id3Text("TPE2", "Album Artist"),
		id3Text("TALB", "Album"), id3Text("TCON", "(17)"), id3Text("TRCK", "3/12"),
		id3Text("TPOS", "2/2"), id3Text("TYER", "2004"),
		id3APIC(4, "image/jpeg", back), id3APIC(3, "image/jpeg", front),
	)
	tags := readBytes(t, cat(tag, mp3Frames(4, 100)))
	want := Tags{Title: "Song", Artist: "Artist", AlbumArtist: "Album Artist", Album: "Album", Genre: "Rock", TrackNo: 3, DiscNo: 2, Year: 2004}
	got := tags
	got.Duration, got.DurationExact, got.Picture = 0, false, nil
	if got != want {
		t.Errorf("tags = %+v, want %+v", got, want)
	}
	// 100 frames of 1152 samples at 44.1 kHz, from the Info header.
	wantDuration(t, tags, 2612244897, true)
	wantPicture(t, tags, "image/jpeg", front)
}

func TestReadMP3WithoutVBRHeaderEstimates(t *testing.T) {
	frames := mp3Frames(40, 0)
	tags := readBytes(t, cat(frames, id3v1("Old Song")))
	if tags.Title != "Old Song" {
		t.Errorf("Title = %q, want the ID3v1 title", tags.Title)
	}
	// The ID3v1 trailer is not audio: 40*417 bytes at 128 kbit/s.
	wantDuration(t, tags, time.Duration(float64(len(frames))*8/128000*float64(time.Second)), false)
}

func TestReadADTSEstimates(t *testing.T) {
	tags := readBytes(t, adtsFrames(50, 200))
	// 50 frames of 1024 samples at 44.1 kHz.
	wantDuration(t, tags, 50*1024*time.Second/44100, false)
}

func TestReadFLAC(t *testing.T) {
	img := fakeJPEG(5)
	tags := readBytes(t, flacFile(441000, 44100,
		flacBlock(4, false, vorbisComment("TITLE=Song", "ARTIST=Artist", "ALBUM=Album", "TRACKNUMBER=3/12", "DISCNUMBER=1", "DATE=2004", "GENRE=Jazz")),
		flacBlock(1, false, make([]byte, 100)),
		flacBlock(6, false, picture3("image/jpeg", img)),
	))
	if tags.Title != "Song" || tags.Artist != "Artist" || tags.Album != "Album" || tags.TrackNo != 3 || tags.DiscNo != 1 || tags.Year != 2004 || tags.Genre != "Jazz" {
		t.Errorf("tags = %+v", tags)
	}
	wantDuration(t, tags, 10*time.Second, true)
	wantPicture(t, tags, "image/jpeg", img)
}

func TestReadOggVorbis(t *testing.T) {
	img := []byte("\x89PNG\r\n\x1a\nnot really")
	tags := readBytes(t, oggVorbisFile(44100, 441000, "TITLE=Song", "ARTIST=Artist", pictureComment(picture3("image/png", img))))
	if tags.Title != "Song" || tags.Artist != "Artist" {
		t.Errorf("tags = %+v", tags)
	}
	wantDuration(t, tags, 10*time.Second, true)
	wantPicture(t, tags, "image/png", img)
}

func TestReadOpusSubtractsPreSkip(t *testing.T) {
	tags := readBytes(t, opusFile(312, 5*48000, "TITLE=Song"))
	if tags.Title != "Song" {
		t.Errorf("Title = %q", tags.Title)
	}
	wantDuration(t, tags, 5*time.Second, true)
}

func TestReadM4A(t *testing.T) {
	img := fakeJPEG(6)
	tags := readBytes(t, m4aFile(1000, 5000,
		textItem("\xa9nam", "Song"), textItem("\xa9ART", "Artist"), textItem("aART", "Album Artist"),
		textItem("\xa9alb", "Album"), textItem("\xa9gen", "Pop"), textItem("\xa9day", "2010-05-01"),
		atom("trkn", dataAtom(0, []byte{0, 0, 0, 7, 0, 9, 0, 0})),
		atom("covr", dataAtom(13, img)),
	))
	if tags.Title != "Song" || tags.Artist != "Artist" || tags.AlbumArtist != "Album Artist" || tags.Album != "Album" || tags.Genre != "Pop" || tags.Year != 2010 || tags.TrackNo != 7 {
		t.Errorf("tags = %+v", tags)
	}
	wantDuration(t, tags, 5*time.Second, true)
	wantPicture(t, tags, "image/jpeg", img)
}

func TestReadM4AWithMoovAfterMdat(t *testing.T) {
	f := m4aFile(1000, 2500, textItem("\xa9nam", "Late"))
	// Move mdat in front of moov, as a streaming-unfriendly encoder writes it.
	ftypLen, moovEnd := 24, len(f)-136
	moved := cat(f[:ftypLen], f[moovEnd:], f[ftypLen:moovEnd])
	tags := readBytes(t, moved)
	if tags.Title != "Late" {
		t.Errorf("Title = %q", tags.Title)
	}
	wantDuration(t, tags, 2500*time.Millisecond, true)
}

func TestReadWAV(t *testing.T) {
	info := riffChunk("LIST", cat([]byte("INFO"),
		riffChunk("INAM", []byte("Info Title\x00")), riffChunk("IART", []byte("Caf\xe9\x00")),
		riffChunk("IPRD", []byte("Album\x00")), riffChunk("ICRD", []byte("1999-01-01\x00")), riffChunk("ITRK", []byte("4\x00"))))
	tags := readBytes(t, wavFile(wavFmt(1000), riffChunk("data", make([]byte, 3000)), info))
	if tags.Title != "Info Title" || tags.Artist != "Café" || tags.Album != "Album" || tags.Year != 1999 || tags.TrackNo != 4 {
		t.Errorf("tags = %+v", tags)
	}
	wantDuration(t, tags, 3*time.Second, true)
}

func TestReadWAVPrefersID3Chunk(t *testing.T) {
	img := fakeJPEG(7)
	info := riffChunk("LIST", cat([]byte("INFO"), riffChunk("INAM", []byte("Info\x00")), riffChunk("IART", []byte("Info Artist\x00"))))
	id3 := riffChunk("id3 ", id3v23(id3Text("TIT2", "ID3 Title"), id3APIC(3, "image/jpeg", img)))
	tags := readBytes(t, wavFile(wavFmt(1000), info, riffChunk("data", make([]byte, 500)), id3))
	if tags.Title != "ID3 Title" || tags.Artist != "Info Artist" {
		t.Errorf("tags = %+v, want the ID3 title over INFO's and INFO's artist kept", tags)
	}
	wantDuration(t, tags, 500*time.Millisecond, true)
	wantPicture(t, tags, "image/jpeg", img)
}

func TestReadWMA(t *testing.T) {
	back, front := fakeJPEG(8), fakeJPEG(9)
	tags := readBytes(t, asfFile(
		asfFileProps(60_000_000, 3000),
		asfContent("Song", "Artist"),
		asfExtended(
			asfDescriptor{"WM/AlbumTitle", asfString, utf16z("Album")},
			asfDescriptor{"WM/AlbumArtist", asfString, utf16z("Album Artist")},
			asfDescriptor{"WM/Genre", asfString, utf16z("Folk")},
			asfDescriptor{"WM/Year", asfString, utf16z("1999")},
			asfDescriptor{"WM/TrackNumber", asfDWord, le32(7)},
			asfDescriptor{"WM/PartOfSet", asfString, utf16z("2/3")},
			asfDescriptor{"WM/Picture", asfBytes, asfPictureValue(4, "image/jpeg", back)},
			asfDescriptor{"WM/Picture", asfBytes, asfPictureValue(3, "image/jpeg", front)},
		),
	))
	want := Tags{Title: "Song", Artist: "Artist", AlbumArtist: "Album Artist", Album: "Album", Genre: "Folk", TrackNo: 7, DiscNo: 2, Year: 1999}
	got := tags
	got.Duration, got.DurationExact, got.Picture = 0, false, nil
	if got != want {
		t.Errorf("tags = %+v, want %+v", got, want)
	}
	// 6 s of play duration less 3 s of preroll.
	wantDuration(t, tags, 3*time.Second, true)
	wantPicture(t, tags, "image/jpeg", front)
}

func TestReadWMAZeroBasedTrack(t *testing.T) {
	tags := readBytes(t, asfFile(asfExtended(asfDescriptor{"WM/Track", asfDWord, le32(4)})))
	if tags.TrackNo != 5 {
		t.Errorf("TrackNo = %d, want WM/Track 4 read as track 5", tags.TrackNo)
	}
}

func TestReadPicture(t *testing.T) {
	img := fakeJPEG(10)
	f := flacFile(44100, 44100, flacBlock(6, false, picture3("image/jpeg", img)))
	res, err := ReadPicture(ReadPictureParams{File: bytes.NewReader(f), Size: int64(len(f))})
	if err != nil {
		t.Fatalf("ReadPicture: %v", err)
	}
	if res.MIMEType != "image/jpeg" || !bytes.Equal(res.Data, img) {
		t.Errorf("ReadPicture = %s, %d bytes; want image/jpeg, %d bytes", res.MIMEType, len(res.Data), len(img))
	}

	bare := opusFile(0, 48000)
	if _, err := ReadPicture(ReadPictureParams{File: bytes.NewReader(bare), Size: int64(len(bare))}); !errors.Is(err, ErrNoPicture) {
		t.Errorf("ReadPicture without a picture = %v, want ErrNoPicture", err)
	}
}

func TestReadSniffsPictureType(t *testing.T) {
	img := fakeJPEG(11)
	// ID3 writers often put "jpg" or nothing where the MIME type belongs.
	tags := readBytes(t, cat(id3v23(id3APIC(3, "jpg", img)), mp3Frames(2, 0)))
	wantPicture(t, tags, "image/jpeg", img)
}

func TestReadUntaggedFileIsNotAnError(t *testing.T) {
	tags := readBytes(t, mp3Frames(10, 0))
	if tags.Title != "" || tags.Duration == 0 {
		t.Errorf("tags = %+v, want no tags and a duration", tags)
	}
}

func TestReadUnsupported(t *testing.T) {
	for name, b := range map[string][]byte{
		"empty": nil,
		"text":  []byte("this is a plain text file, not audio"),
		"png":   []byte("\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR"),
	} {
		if _, err := Read(ReadParams{File: bytes.NewReader(b), Size: int64(len(b))}); !errors.Is(err, ErrUnsupported) {
			t.Errorf("%s: Read = %v, want ErrUnsupported", name, err)
		}
	}
}

// TestReadRecoversLibraryPanic feeds the tag library an MP4 title atom typed
// as a JPEG. The library stores a picture where it later asserts a string
// and panics; that has to cost this file, not the process.
func TestReadRecoversLibraryPanic(t *testing.T) {
	f := m4aFile(1000, 1000, atom("\xa9nam", dataAtom(13, fakeJPEG(12))))
	_, err := Read(ReadParams{File: bytes.NewReader(f), Size: int64(len(f))})
	if !errors.Is(err, ErrMalformed) {
		t.Fatalf("Read = %v, want ErrMalformed from the recovered panic", err)
	}
}

func TestReadCleansText(t *testing.T) {
	long := string(bytes.Repeat([]byte("é"), maxTextBytes))
	tags := readBytes(t, flacFile(1, 1, flacBlock(4, false, vorbisComment("TITLE=  padded \x00\x00", "ARTIST="+long))))
	if tags.Title != "padded" {
		t.Errorf("Title = %q, want trimmed", tags.Title)
	}
	if len(tags.Artist) > maxTextBytes || len(tags.Artist)%2 != 0 {
		t.Errorf("Artist is %d bytes, want at most %d cut on a rune boundary", len(tags.Artist), maxTextBytes)
	}
}
