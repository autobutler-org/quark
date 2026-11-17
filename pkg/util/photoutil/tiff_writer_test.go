package photoutil

// cspell:ignore IFDs PackBits nacc nbits differenced

import (
	"bytes"
	"compress/zlib"
	"encoding/binary"
	"testing"
)

// testByteOrder reads and appends in one byte order.
type testByteOrder interface {
	binary.ByteOrder
	binary.AppendByteOrder
}

// testTIFF describes a TIFF for writeTestTIFF to build. Zero values pick
// the plain case: strips, no compression, no predictor, 8-bit, chunky.
type testTIFF struct {
	order       testByteOrder
	width       int
	height      int
	samples     int // samples per pixel; 1 when zero
	bits        int // 8 or 16; 8 when zero
	compression int
	predictor   int
	photometric int // -1 omits the tag; 0 picks gray or RGB from samples
	// rowsPerStrip, or tileWidth and tileLength for a tiled image.
	rowsPerStrip          int
	tileWidth, tileLength int
	newSubfileType        int
	planarConfig          int
	sampleFormat          int
	extraSample           int // 0 omits the tag
	orientation           int // 0 omits the tag
	pixel                 func(x, y, c int) uint16
	repeatFirstChunk      bool // every strip or tile is a copy of the first
	bogusData             bool // chunk offsets point past the end of the file
	subIFDs               []testTIFF
	next                  *testTIFF
	skipData              bool // no strips or tiles are written at all
}

func (s *testTIFF) defaults() {
	if s.order == nil {
		s.order = binary.LittleEndian
	}
	if s.samples == 0 {
		s.samples = 1
	}
	if s.bits == 0 {
		s.bits = 8
	}
	if s.compression == 0 {
		s.compression = tiffCompressionNone
	}
	if s.photometric == 0 {
		s.photometric = tiffPhotometricBlackIsZero
		if s.samples >= 3 {
			s.photometric = tiffPhotometricRGB
		}
	}
	if s.pixel == nil {
		s.pixel = func(x, y, c int) uint16 { return uint16((x*7 + y*13 + c*50) * 257) }
	}
}

// sample is the stored value of channel c at (x, y) at the image's depth.
func (s *testTIFF) sample(x, y, c int) uint16 {
	v := s.pixel(x, y, c)
	if s.bits == 8 {
		return v >> 8
	}
	return v
}

// writeTestTIFF builds the TIFF s describes. Pixel data comes first, then
// every directory.
func writeTestTIFF(t *testing.T, s testTIFF) []byte {
	t.Helper()
	var out bytes.Buffer
	s.defaults()
	if s.order == binary.LittleEndian {
		out.WriteString("II*\x00")
	} else {
		out.WriteString("MM\x00*")
	}
	out.Write(make([]byte, 4)) // IFD0 offset, patched below
	off := writeTestIFD(t, &out, s)
	b := out.Bytes()
	s.order.PutUint32(b[4:], uint32(off))
	return b
}

// writeTestIFD writes s's pixel data, its SubIFDs and next directory, and
// then its own directory, returning the directory's offset.
func writeTestIFD(t *testing.T, out *bytes.Buffer, s testTIFF) int {
	t.Helper()
	s.defaults()
	var offsets, counts []uint32
	tiled := s.tileWidth > 0
	if !s.skipData {
		var chunks [][]byte
		if tiled {
			for ty := 0; ty < (s.height+s.tileLength-1)/s.tileLength; ty++ {
				for tx := 0; tx < (s.width+s.tileWidth-1)/s.tileWidth; tx++ {
					if s.repeatFirstChunk && len(chunks) > 0 {
						chunks = append(chunks, chunks[0])
						continue
					}
					chunks = append(chunks, encodeTestChunk(t, &s, tx*s.tileWidth, ty*s.tileLength, s.tileWidth, s.tileLength))
				}
			}
		} else {
			rps := s.rowsPerStrip
			if rps == 0 {
				rps = s.height
			}
			for y := 0; y < s.height; y += rps {
				if s.repeatFirstChunk && len(chunks) > 0 {
					chunks = append(chunks, chunks[0])
					continue
				}
				chunks = append(chunks, encodeTestChunk(t, &s, 0, y, s.width, min(rps, s.height-y)))
			}
		}
		for _, c := range chunks {
			off := uint32(out.Len())
			if s.bogusData {
				off = 1 << 30
			}
			offsets = append(offsets, off)
			counts = append(counts, uint32(len(c)))
			if !s.bogusData {
				out.Write(c)
			}
		}
	}

	var subOffsets []uint32
	for _, sub := range s.subIFDs {
		subOffsets = append(subOffsets, uint32(writeTestIFD(t, out, sub)))
	}
	next := 0
	if s.next != nil {
		next = writeTestIFD(t, out, *s.next)
	}

	type entry struct {
		tag, typ uint16
		values   []uint32
	}
	short := func(tag int, v ...int) entry {
		e := entry{tag: uint16(tag), typ: 3}
		for _, x := range v {
			e.values = append(e.values, uint32(x))
		}
		return e
	}
	long := func(tag int, v []uint32) entry { return entry{tag: uint16(tag), typ: 4, values: v} }
	bits := make([]int, s.samples)
	for i := range bits {
		bits[i] = s.bits
	}
	entries := []entry{
		long(tiffTagNewSubfileType, []uint32{uint32(s.newSubfileType)}),
		long(tiffTagImageWidth, []uint32{uint32(s.width)}),
		long(tiffTagImageLength, []uint32{uint32(s.height)}),
		short(tiffTagBitsPerSample, bits...),
		short(tiffTagCompression, s.compression),
	}
	if s.photometric >= 0 {
		entries = append(entries, short(tiffTagPhotometric, s.photometric))
	}
	if s.orientation != 0 {
		entries = append(entries, short(tiffTagOrientation, s.orientation))
	}
	entries = append(entries, short(tiffTagSamplesPerPixel, s.samples))
	if tiled {
		entries = append(entries,
			short(tiffTagTileWidth, s.tileWidth), short(tiffTagTileLength, s.tileLength),
			long(tiffTagTileOffsets, offsets), long(tiffTagTileByteCounts, counts))
	} else {
		rps := s.rowsPerStrip
		if rps == 0 {
			rps = s.height
		}
		entries = append(entries,
			long(tiffTagStripOffsets, offsets), long(tiffTagRowsPerStrip, []uint32{uint32(rps)}),
			long(tiffTagStripByteCounts, counts))
	}
	if s.planarConfig != 0 {
		entries = append(entries, short(tiffTagPlanarConfig, s.planarConfig))
	}
	if s.predictor != 0 {
		entries = append(entries, short(tiffTagPredictor, s.predictor))
	}
	if len(subOffsets) > 0 {
		entries = append(entries, entry{tag: tiffTagSubIFDs, typ: 13, values: subOffsets})
	}
	if s.extraSample != 0 {
		entries = append(entries, short(tiffTagExtraSamples, s.extraSample))
	}
	if s.sampleFormat != 0 {
		formats := make([]int, s.samples)
		for i := range formats {
			formats[i] = s.sampleFormat
		}
		entries = append(entries, short(tiffTagSampleFormat, formats...))
	}
	// Tags must be in ascending order.
	for i := 1; i < len(entries); i++ {
		for j := i; j > 0 && entries[j].tag < entries[j-1].tag; j-- {
			entries[j], entries[j-1] = entries[j-1], entries[j]
		}
	}

	// Values over four bytes go before the directory.
	encode := func(e entry) []byte {
		var b []byte
		for _, v := range e.values {
			if e.typ == 3 {
				b = s.order.AppendUint16(b, uint16(v))
			} else {
				b = s.order.AppendUint32(b, v)
			}
		}
		return b
	}
	valueOffsets := make([]uint32, len(entries))
	for i, e := range entries {
		if b := encode(e); len(b) > 4 {
			if out.Len()%2 == 1 {
				out.WriteByte(0)
			}
			valueOffsets[i] = uint32(out.Len())
			out.Write(b)
		}
	}
	if out.Len()%2 == 1 {
		out.WriteByte(0)
	}
	dirOff := out.Len()
	var d []byte
	d = s.order.AppendUint16(d, uint16(len(entries)))
	for i, e := range entries {
		d = s.order.AppendUint16(d, e.tag)
		d = s.order.AppendUint16(d, e.typ)
		d = s.order.AppendUint32(d, uint32(len(e.values)))
		if b := encode(e); len(b) > 4 {
			d = s.order.AppendUint32(d, valueOffsets[i])
		} else {
			d = append(d, append(b, make([]byte, 4-len(b))...)...)
		}
	}
	d = s.order.AppendUint32(d, uint32(next))
	out.Write(d)
	return dirOff
}

// encodeTestChunk encodes the w × h block at (x0, y0) as one strip or tile:
// samples in byte order, differenced per row under predictor 2, then
// compressed. Pixels outside the image are zero.
func encodeTestChunk(t *testing.T, s *testTIFF, x0, y0, w, h int) []byte {
	t.Helper()
	var raw []byte
	for y := y0; y < y0+h; y++ {
		row := make([]uint16, w*s.samples)
		for x := range w {
			for c := range s.samples {
				if x0+x < s.width && y < s.height {
					row[x*s.samples+c] = s.sample(x0+x, y, c)
				}
			}
		}
		if s.predictor == 2 {
			for i := len(row) - 1; i >= s.samples; i-- {
				row[i] -= row[i-s.samples]
			}
		}
		for _, v := range row {
			if s.bits == 8 {
				raw = append(raw, byte(v))
			} else {
				raw = s.order.AppendUint16(raw, v)
			}
		}
	}
	switch s.compression {
	case tiffCompressionLZW:
		return encodeTestLZW(raw)
	case tiffCompressionDeflate, tiffCompressionDeflateOld:
		var b bytes.Buffer
		zw := zlib.NewWriter(&b)
		_, _ = zw.Write(raw)
		_ = zw.Close()
		return b.Bytes()
	case tiffCompressionPackBits:
		return encodeTestPackBits(raw)
	}
	return raw
}

// encodeTestLZW is TIFF's LZW: MSB-first codes, a clear code first, and the
// code width growing one code early, as libtiff writes it.
func encodeTestLZW(data []byte) []byte {
	const clearCode, eoiCode, firstCode, maxCode = 256, 257, 258, 4095
	var out []byte
	var acc uint32
	var nacc uint
	nbits := uint(9)
	put := func(code int) {
		acc = acc<<nbits | uint32(code)
		nacc += nbits
		for nacc >= 8 {
			out = append(out, byte(acc>>(nacc-8)))
			nacc -= 8
		}
	}
	var table [4096][256]uint16
	reset := func() {
		for i := range table {
			table[i] = [256]uint16{}
		}
	}
	free := firstCode
	put(clearCode)
	grow := func() {
		free++
		if free == maxCode-1 {
			put(clearCode) // still at the old width
			reset()
			free = firstCode
			nbits = 9
		} else if free > (1<<nbits)-1 {
			nbits++
		}
	}
	prefix := -1
	for _, c := range data {
		if prefix < 0 {
			prefix = int(c)
			continue
		}
		if code := table[prefix][c]; code != 0 {
			prefix = int(code)
			continue
		}
		put(prefix)
		table[prefix][c] = uint16(free)
		grow()
		prefix = int(c)
	}
	if prefix >= 0 {
		put(prefix)
		free++
		if free > (1<<nbits)-1 && free != maxCode-1 {
			nbits++
		}
	}
	put(eoiCode)
	if nacc > 0 {
		out = append(out, byte(acc<<(8-nacc)))
	}
	return out
}

// encodeTestPackBits writes runs of three or more equal bytes as repeats and
// everything else as literals, so a test exercises both.
func encodeTestPackBits(data []byte) []byte {
	var out []byte
	for i := 0; i < len(data); {
		run := 1
		for i+run < len(data) && data[i+run] == data[i] && run < 128 {
			run++
		}
		if run >= 3 {
			out = append(out, byte(int8(1-run)), data[i])
			i += run
			continue
		}
		j := i
		for j < len(data) && j-i < 128 {
			if j+2 < len(data) && data[j] == data[j+1] && data[j] == data[j+2] {
				break
			}
			j++
		}
		out = append(out, byte(j-i-1))
		out = append(out, data[i:j]...)
		i = j
	}
	return out
}
