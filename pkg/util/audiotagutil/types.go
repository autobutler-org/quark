package audiotagutil

import (
	"encoding/binary"
	"errors"
	"io"
)

// errBudget is what budgetReader returns once its budget is spent. The tag
// library flattens the errors it wraps, so budgetReader also records that it
// happened.
var errBudget = errors.New("audiotagutil: read budget spent")

// parsed is everything one read of a file found.
type parsed struct {
	tags    Tags
	picture *picture
}

// picture is an embedded picture before it is reduced to a PictureRef.
type picture struct {
	mimeType string
	data     []byte
}

// mpegHeader is one decoded MPEG audio frame header.
type mpegHeader struct {
	mpeg1           bool
	layer           int
	mono            bool
	bitrate         int // bits per second
	sampleRate      int
	samplesPerFrame int
	frameLen        int
}

// mp4Box is one atom: its type, where it starts, its header length and its
// whole length.
type mp4Box struct {
	name     string
	off, hdr int64
	n        int64
}

// budgetReader is the only view of a file the tag library gets: a section the
// caller has already checked, which seeks freely but stops after MaxTagBytes
// have been read from it. The library's large reads grow a buffer as bytes
// arrive, so the budget bounds them too.
type budgetReader struct {
	r     *io.SectionReader
	left  int64
	spent bool
}

func newBudgetReader(src io.ReaderAt, off, n int64) *budgetReader {
	return &budgetReader{r: io.NewSectionReader(src, off, n), left: MaxTagBytes}
}

func (b *budgetReader) Read(p []byte) (int, error) {
	if b.left <= 0 {
		b.spent = true
		return 0, errBudget
	}
	if int64(len(p)) > b.left {
		p = p[:b.left]
	}
	n, err := b.r.Read(p)
	b.left -= int64(n)
	return n, err
}

func (b *budgetReader) Seek(offset int64, whence int) (int64, error) {
	return b.r.Seek(offset, whence)
}

// fieldReader walks length-prefixed fields inside a structure of a known
// length, refusing any declared length longer than what is left of it. It
// never allocates for a field: a skipped field is a seek when the underlying
// reader can seek, and is discarded through a fixed buffer otherwise.
type fieldReader struct {
	r    io.Reader
	left int64
	buf  [8]byte
}

// take reserves n bytes of what is left, or fails with ErrTagTooLarge.
func (f *fieldReader) take(n int64) error {
	if n < 0 || n > f.left {
		return ErrTagTooLarge
	}
	f.left -= n
	return nil
}

func (f *fieldReader) small(n int) ([]byte, error) {
	if err := f.take(int64(n)); err != nil {
		return nil, err
	}
	if _, err := io.ReadFull(f.r, f.buf[:n]); err != nil {
		return nil, ErrMalformed
	}
	return f.buf[:n], nil
}

func (f *fieldReader) u32(order binary.ByteOrder) (uint32, error) {
	b, err := f.small(4)
	if err != nil {
		return 0, err
	}
	return order.Uint32(b), nil
}

// prefix reads the first n bytes of a field into p, which must hold n.
func (f *fieldReader) prefix(p []byte) error {
	if err := f.take(int64(len(p))); err != nil {
		return err
	}
	if _, err := io.ReadFull(f.r, p); err != nil {
		return ErrMalformed
	}
	return nil
}

func (f *fieldReader) skip(n int64) error {
	if err := f.take(n); err != nil {
		return err
	}
	if s, ok := f.r.(io.Seeker); ok {
		if _, err := s.Seek(n, io.SeekCurrent); err != nil {
			return ErrMalformed
		}
		return nil
	}
	if _, err := io.CopyN(io.Discard, f.r, n); err != nil {
		return ErrMalformed
	}
	return nil
}
