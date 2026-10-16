package audiotagutil

import (
	"bytes"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"math"
	"net/http"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/dhowden/tag"
)

// maxTextBytes caps one text field. A title is never this long, and a tag that
// claims otherwise should not put megabytes into every row built from it.
const maxTextBytes = 1024

// maxBoxes caps how many chunks, atoms or blocks one structure may hold
// before it is refused, so a file of empty boxes cannot spin a walk for
// billions of iterations.
const maxBoxes = 4096

// frontCover is the picture type the tag library gives a front cover.
const frontCover = "Cover (front)"

// asfHeaderGUID opens every ASF (wma, wmv) file.
var asfHeaderGUID = []byte{0x30, 0x26, 0xB2, 0x75, 0x8E, 0x66, 0xCF, 0x11, 0xA6, 0xD9, 0x00, 0xAA, 0x00, 0x62, 0xCE, 0x6C}

// read detects the format from the file's first bytes and hands it to that
// format's reader.
func read(src io.ReaderAt, size int64) (parsed, error) {
	if src == nil || size < 12 {
		return parsed{}, ErrUnsupported
	}
	head := make([]byte, 16)
	if err := readFull(src, 0, head); err != nil {
		head = head[:12]
		if err := readFull(src, 0, head); err != nil {
			return parsed{}, ErrUnsupported
		}
	}
	switch {
	case string(head[0:4]) == "fLaC":
		return readFLAC(src, size)
	case string(head[0:4]) == "OggS":
		return readOgg(src, size)
	case string(head[4:8]) == "ftyp":
		return readMP4(src, size)
	case string(head[0:4]) == "RIFF" && string(head[8:12]) == "WAVE":
		return readWAV(src, size)
	case len(head) == 16 && bytes.Equal(head, asfHeaderGUID):
		return readASF(src, size)
	case string(head[0:3]) == "ID3", head[0] == 0xFF && head[1]&0xE0 == 0xE0:
		return readMPEG(src, size)
	}
	return parsed{}, ErrUnsupported
}

// readFull fills p from src at off, failing on a short read.
func readFull(src io.ReaderAt, off int64, p []byte) error {
	n, err := src.ReadAt(p, off)
	if n == len(p) {
		return nil
	}
	if err == nil || errors.Is(err, io.EOF) {
		return io.ErrUnexpectedEOF
	}
	return err
}

// readRegion reads n bytes at off after checking n against MaxTagBytes and
// the file's size. It is how every in-memory parse here gets its bytes.
func readRegion(src io.ReaderAt, size, off, n int64) ([]byte, error) {
	if n < 0 || n > MaxTagBytes || off < 0 || n > size-off {
		return nil, ErrTagTooLarge
	}
	b := make([]byte, n)
	if err := readFull(src, off, b); err != nil {
		return nil, ErrMalformed
	}
	return b, nil
}

// libraryTags runs one of the tag library's readers over a section of the
// file this package has already checked. A panic or an error in the library
// costs this file only.
func libraryTags(src io.ReaderAt, off, n int64, readTags func(io.ReadSeeker) (tag.Metadata, error)) (found parsed, err error) {
	br := newBudgetReader(src, off, n)
	defer func() {
		if r := recover(); r != nil {
			found, err = parsed{}, fmt.Errorf("%w: tag reader panicked: %v", ErrMalformed, r)
		}
	}()
	m, err := readTags(br)
	switch {
	case br.spent:
		return parsed{}, ErrTagTooLarge
	case errors.Is(err, tag.ErrNoTagsFound), errors.Is(err, tag.ErrNotID3v1):
		return parsed{}, nil
	case err != nil:
		return parsed{}, fmt.Errorf("%w: %v", ErrMalformed, err)
	}
	return parsed{tags: metadataTags(m), picture: libraryPicture(m)}, nil
}

// metadataTags copies the library's metadata into Tags.
func metadataTags(m tag.Metadata) Tags {
	track, _ := m.Track()
	disc, _ := m.Disc()
	if m.Format() == tag.VORBIS {
		// The library parses "3/12" as no track at all.
		raw := m.Raw()
		if track == 0 {
			track = leadingInt(rawString(raw, "tracknumber"))
		}
		if disc == 0 {
			disc = leadingInt(rawString(raw, "discnumber"))
		}
	}
	return Tags{
		Title:       cleanText(m.Title()),
		Artist:      cleanText(m.Artist()),
		AlbumArtist: cleanText(m.AlbumArtist()),
		Album:       cleanText(m.Album()),
		Genre:       cleanText(m.Genre()),
		TrackNo:     clampCount(track),
		DiscNo:      clampCount(disc),
		Year:        clampYear(m.Year()),
	}
}

func rawString(raw map[string]interface{}, key string) string {
	s, _ := raw[key].(string)
	return s
}

// libraryPicture picks the front cover when ID3 frames carry several pictures,
// else the first, else whatever the library offers.
func libraryPicture(m tag.Metadata) *picture {
	raw := m.Raw()
	var first *tag.Picture
	for _, base := range []string{"APIC", "PIC"} {
		for i := -1; ; i++ {
			key := base
			if i >= 0 {
				key = base + "_" + strconv.Itoa(i)
			}
			v, ok := raw[key]
			if !ok {
				break
			}
			p, ok := v.(*tag.Picture)
			if !ok || p == nil || len(p.Data) == 0 {
				continue
			}
			if p.Type == frontCover {
				return newPicture(p.MIMEType, p.Data)
			}
			if first == nil {
				first = p
			}
		}
	}
	if first == nil {
		first = m.Picture()
	}
	if first == nil || len(first.Data) == 0 {
		return nil
	}
	return newPicture(first.MIMEType, first.Data)
}

// newPicture keeps a picture's bytes, sniffing the media type when the tag
// gave none or something other than an image type.
func newPicture(mimeType string, data []byte) *picture {
	mimeType = strings.ToLower(strings.TrimSpace(mimeType))
	if !strings.HasPrefix(mimeType, "image/") {
		mimeType = http.DetectContentType(data)
	}
	return &picture{mimeType: mimeType, data: data}
}

func pictureRef(p *picture) *PictureRef {
	sum := sha256.Sum256(p.data)
	return &PictureRef{MIMEType: p.mimeType, Size: int64(len(p.data)), SHA256: hex.EncodeToString(sum[:])}
}

// mergeTags overlays the non-empty fields of over onto base.
func mergeTags(base, over Tags) Tags {
	pick := func(a, b string) string {
		if b != "" {
			return b
		}
		return a
	}
	pickInt := func(a, b int) int {
		if b != 0 {
			return b
		}
		return a
	}
	base.Title = pick(base.Title, over.Title)
	base.Artist = pick(base.Artist, over.Artist)
	base.AlbumArtist = pick(base.AlbumArtist, over.AlbumArtist)
	base.Album = pick(base.Album, over.Album)
	base.Genre = pick(base.Genre, over.Genre)
	base.TrackNo = pickInt(base.TrackNo, over.TrackNo)
	base.DiscNo = pickInt(base.DiscNo, over.DiscNo)
	base.Year = pickInt(base.Year, over.Year)
	return base
}

// cleanText makes a tag value safe to store: valid UTF-8, no padding NULs or
// surrounding space, and at most maxTextBytes long.
func cleanText(s string) string {
	if len(s) > 4*maxTextBytes {
		s = s[:4*maxTextBytes]
	}
	s = strings.ToValidUTF8(s, "")
	s = strings.TrimSpace(strings.Trim(s, "\x00"))
	if i := strings.IndexByte(s, 0); i >= 0 {
		s = strings.TrimSpace(s[:i])
	}
	if len(s) > maxTextBytes {
		cut := maxTextBytes
		for cut > 0 && !utf8.RuneStart(s[cut]) {
			cut--
		}
		s = s[:cut]
	}
	return s
}

// latin1OrUTF8 decodes a RIFF INFO string, which has no declared encoding:
// UTF-8 when it is valid UTF-8, Latin-1 otherwise.
func latin1OrUTF8(b []byte) string {
	if len(b) > 4*maxTextBytes {
		b = b[:4*maxTextBytes]
	}
	if utf8.Valid(b) {
		return cleanText(string(b))
	}
	r := make([]rune, len(b))
	for i, c := range b {
		r[i] = rune(c)
	}
	return cleanText(string(r))
}

// leadingInt parses the digits that open s, so "3/12" is 3 and "2004-05-01"
// is 2004. Anything else is 0.
func leadingInt(s string) int {
	s = strings.TrimSpace(s)
	end := 0
	for end < len(s) && end < 9 && s[end] >= '0' && s[end] <= '9' {
		end++
	}
	n, _ := strconv.Atoi(s[:end])
	return n
}

func clampCount(n int) int {
	if n < 0 || n > 9999 {
		return 0
	}
	return n
}

func clampYear(n int) int {
	if n < 1 || n > 9999 {
		return 0
	}
	return n
}

// samplesDuration converts a sample count at a rate into a duration, or
// reports false when either is unusable or the result would overflow.
func samplesDuration(samples, rate uint64) (time.Duration, bool) {
	if samples == 0 || rate == 0 {
		return 0, false
	}
	secs := samples / rate
	if secs > math.MaxInt64/uint64(time.Second)-1 {
		return 0, false
	}
	frac := (samples % rate) * uint64(time.Second) / rate
	return time.Duration(secs)*time.Second + time.Duration(frac), true
}

// estimateDuration is bytes over a byte rate, for formats with no exact count.
func estimateDuration(audioBytes int64, bytesPerSecond float64) (time.Duration, bool) {
	if audioBytes <= 0 || bytesPerSecond <= 0 {
		return 0, false
	}
	secs := float64(audioBytes) / bytesPerSecond
	if secs > float64(math.MaxInt64/int64(time.Second)-1) {
		return 0, false
	}
	return time.Duration(secs * float64(time.Second)), true
}

// metadataBlockPicture is the Vorbis comment key holding a base64 FLAC
// picture block, matched case-insensitively.
const metadataBlockPicture = "metadata_block_picture="

// checkVorbisComment walks a Vorbis comment block of n bytes (vendor string,
// comment count, comments) and refuses any declared length that runs past
// it. A METADATA_BLOCK_PICTURE comment is decoded as it streams by and its
// picture block checked too: the library allocates that picture's declared
// length without looking at the data that is actually there.
func checkVorbisComment(r io.Reader, n int64) error {
	f := &fieldReader{r: r, left: n}
	vendor, err := f.u32(binary.LittleEndian)
	if err != nil {
		return err
	}
	if err := f.skip(int64(vendor)); err != nil {
		return err
	}
	count, err := f.u32(binary.LittleEndian)
	if err != nil {
		return err
	}
	key := make([]byte, len(metadataBlockPicture))
	for i := uint32(0); i < count; i++ {
		l, err := f.u32(binary.LittleEndian)
		if err != nil {
			return err
		}
		length := int64(l)
		if length < int64(len(key)) {
			if err := f.skip(length); err != nil {
				return err
			}
			continue
		}
		if err := f.prefix(key); err != nil {
			return err
		}
		rest := length - int64(len(key))
		if !strings.EqualFold(string(key), metadataBlockPicture) {
			if err := f.skip(rest); err != nil {
				return err
			}
			continue
		}
		if err := f.take(rest); err != nil {
			return err
		}
		decoded := base64.NewDecoder(base64.StdEncoding, io.LimitReader(f.r, rest))
		if err := checkPictureBlock(decoded, rest/4*3); err != nil {
			return err
		}
		if _, err := io.Copy(io.Discard, decoded); err != nil {
			return ErrMalformed
		}
	}
	return nil
}

// checkPictureBlock walks a FLAC picture block of at most n bytes (type, MIME
// type, description, dimensions, data) and refuses any declared length that
// runs past it.
func checkPictureBlock(r io.Reader, n int64) error {
	f := &fieldReader{r: r, left: n}
	if _, err := f.u32(binary.BigEndian); err != nil {
		return err
	}
	for range 2 { // the MIME type, then the description
		l, err := f.u32(binary.BigEndian)
		if err != nil {
			return err
		}
		if err := f.skip(int64(l)); err != nil {
			return err
		}
	}
	if err := f.skip(16); err != nil {
		return err
	}
	dataLen, err := f.u32(binary.BigEndian)
	if err != nil {
		return err
	}
	return f.skip(int64(dataLen))
}
