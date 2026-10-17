package xlsutil

import (
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"unicode/utf16"
)

// next reads one record. The body is only valid until the next call: it is
// read into the reader's one record buffer. io.EOF means the stream ended on
// a record boundary.
func (rr *recordReader) next() (uint16, []byte, error) {
	header := rr.head[:]
	n, err := io.ReadFull(rr.br, header)
	if err != nil {
		if errors.Is(err, io.EOF) && n == 0 {
			return 0, nil, io.EOF
		}
		return 0, nil, rr.readError(err)
	}
	typ := binary.LittleEndian.Uint16(header[0:2])
	size := int(binary.LittleEndian.Uint16(header[2:4]))
	if size > maxRecordBytes {
		return 0, nil, fmt.Errorf("%w: a record of %d bytes, past BIFF8's %d", ErrNotSpreadsheet, size, maxRecordBytes)
	}
	if _, err := io.ReadFull(rr.br, rr.buf[:size]); err != nil {
		return 0, nil, rr.readError(err)
	}
	rr.pos += int64(4 + size)
	return typ, rr.buf[:size], nil
}

// peekType is the type of the next record, without reading it; false when
// the stream has no further record.
func (rr *recordReader) peekType() (uint16, bool) {
	b, err := rr.br.Peek(2)
	if err != nil {
		return 0, false
	}
	return binary.LittleEndian.Uint16(b), true
}

// seek moves to offset in the stream. A target already in the buffer is
// reached by discarding up to it: seeking the container stream backwards
// walks its sector chain again from the start.
func (rr *recordReader) seek(offset int64) error {
	if offset < 0 || offset >= rr.size {
		return fmt.Errorf("%w: a sheet offset outside the stream", ErrNotSpreadsheet)
	}
	if ahead := offset - rr.pos; ahead >= 0 && ahead <= int64(rr.br.Buffered()) {
		_, err := rr.br.Discard(int(ahead))
		rr.pos = offset
		return err
	}
	if _, err := rr.file.Seek(offset, io.SeekStart); err != nil {
		return rr.readError(err)
	}
	rr.br.Reset(rr.file)
	rr.pos = offset
	return nil
}

// readError classifies a failed read of the stream.
func (rr *recordReader) readError(err error) error {
	if errors.Is(err, io.ErrUnexpectedEOF) || errors.Is(err, io.EOF) {
		return fmt.Errorf("%w: the stream ends inside a record", ErrNotSpreadsheet)
	}
	return rr.budget.classify(err)
}

// bytes reads n bytes that may straddle a record boundary, as the header of
// a shared string and its formatting runs may.
func (cr *continuedReader) bytes(n int) ([]byte, error) {
	out := make([]byte, 0, n)
	for len(out) < n {
		if len(cr.data) == 0 {
			if err := cr.advance(); err != nil {
				return nil, err
			}
			continue
		}
		take := min(n-len(out), len(cr.data))
		out = append(out, cr.data[:take]...)
		cr.data = cr.data[take:]
	}
	return out, nil
}

// skip discards n bytes that may straddle record boundaries.
func (cr *continuedReader) skip(n int64) error {
	for n > 0 {
		if len(cr.data) == 0 {
			if err := cr.advance(); err != nil {
				return err
			}
			continue
		}
		take := min(n, int64(len(cr.data)))
		cr.data = cr.data[take:]
		n -= take
	}
	return nil
}

// chars reads a string's character array of cch characters. When the array
// runs on into a CONTINUE record, that record opens with a fresh option byte
// saying whether the rest is stored one byte or two bytes a character.
func (cr *continuedReader) chars(cch int, wide bool) (string, error) {
	units := make([]uint16, 0, cch)
	for len(units) < cch {
		if len(cr.data) == 0 {
			if err := cr.advance(); err != nil {
				return "", err
			}
			if len(cr.data) == 0 {
				return "", fmt.Errorf("%w: an empty CONTINUE inside a string", ErrNotSpreadsheet)
			}
			wide = cr.data[0]&0x01 != 0
			cr.data = cr.data[1:]
			continue
		}
		if wide {
			for len(units) < cch && len(cr.data) >= 2 {
				units = append(units, binary.LittleEndian.Uint16(cr.data))
				cr.data = cr.data[2:]
			}
			if len(units) < cch && len(cr.data) == 1 {
				return "", fmt.Errorf("%w: a character split across records", ErrNotSpreadsheet)
			}
			continue
		}
		for len(units) < cch && len(cr.data) > 0 {
			units = append(units, uint16(cr.data[0]))
			cr.data = cr.data[1:]
		}
	}
	return string(utf16.Decode(units)), nil
}

// advance moves on to the next record, which has to be a CONTINUE.
func (cr *continuedReader) advance() error {
	if typ, ok := cr.rr.peekType(); !ok || typ != recContinue {
		return fmt.Errorf("%w: a value runs past its record", ErrNotSpreadsheet)
	}
	_, data, err := cr.rr.next()
	if err != nil {
		return err
	}
	cr.data = data
	return nil
}

// unicodeString reads an XLUnicodeString — a 16-bit character count, an
// option byte, then the characters — from cr, the form of a formula's
// string result.
func (cr *continuedReader) unicodeString() (string, error) {
	head, err := cr.bytes(3)
	if err != nil {
		return "", err
	}
	cch := int(binary.LittleEndian.Uint16(head))
	return cr.chars(cch, head[2]&0x01 != 0)
}

// richString reads one entry of the shared string table: an
// XLUnicodeRichExtendedString, whose formatting runs and phonetic data
// follow the characters and are skipped.
func (cr *continuedReader) richString() (string, error) {
	head, err := cr.bytes(3)
	if err != nil {
		return "", err
	}
	cch := int(binary.LittleEndian.Uint16(head))
	flags := head[2]
	var runs, ext int64
	if flags&0x08 != 0 {
		b, err := cr.bytes(2)
		if err != nil {
			return "", err
		}
		runs = int64(binary.LittleEndian.Uint16(b))
	}
	if flags&0x04 != 0 {
		b, err := cr.bytes(4)
		if err != nil {
			return "", err
		}
		ext = int64(binary.LittleEndian.Uint32(b))
	}
	text, err := cr.chars(cch, flags&0x01 != 0)
	if err != nil {
		return "", err
	}
	if err := cr.skip(4*runs + ext); err != nil {
		return "", err
	}
	return text, nil
}

// shortString reads a string held whole inside one record body: an 8- or
// 16-bit character count (countBytes), an option byte, then the characters.
// It is the form of a sheet name, a number format and a LABEL cell.
func shortString(b []byte, countBytes int) (string, bool) {
	if len(b) < countBytes+1 {
		return "", false
	}
	cch := int(b[0])
	if countBytes == 2 {
		cch = int(binary.LittleEndian.Uint16(b))
	}
	wide := b[countBytes]&0x01 != 0
	b = b[countBytes+1:]
	if wide {
		if len(b) < 2*cch {
			return "", false
		}
		units := make([]uint16, cch)
		for i := range units {
			units[i] = binary.LittleEndian.Uint16(b[2*i:])
		}
		return string(utf16.Decode(units)), true
	}
	if len(b) < cch {
		return "", false
	}
	runes := make([]rune, cch)
	for i := range runes {
		runes[i] = rune(b[i])
	}
	return string(runes), true
}
