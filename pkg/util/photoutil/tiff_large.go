package photoutil

// cspell:ignore IFDs IFD's PackBits YCbCr CMYK

import (
	"bufio"
	"bytes"
	"compress/zlib"
	"encoding/binary"
	"errors"
	"fmt"
	"image"
	"io"

	"golang.org/x/image/tiff/lzw"
)

// The TIFF tags the large-image path reads.
const (
	tiffTagNewSubfileType  = 254
	tiffTagImageWidth      = 256
	tiffTagImageLength     = 257
	tiffTagBitsPerSample   = 258
	tiffTagCompression     = 259
	tiffTagPhotometric     = 262
	tiffTagStripOffsets    = 273
	tiffTagOrientation     = 274
	tiffTagSamplesPerPixel = 277
	tiffTagRowsPerStrip    = 278
	tiffTagStripByteCounts = 279
	tiffTagPlanarConfig    = 284
	tiffTagPredictor       = 317
	tiffTagTileWidth       = 322
	tiffTagTileLength      = 323
	tiffTagTileOffsets     = 324
	tiffTagTileByteCounts  = 325
	tiffTagSubIFDs         = 330
	tiffTagExtraSamples    = 338
	tiffTagSampleFormat    = 339
)

// The compressions the streaming decoder reads.
const (
	tiffCompressionNone        = 1
	tiffCompressionLZW         = 5
	tiffCompressionDeflate     = 8
	tiffCompressionPackBits    = 32773
	tiffCompressionDeflateOld  = 32946
	tiffPhotometricWhiteIsZero = 0
	tiffPhotometricBlackIsZero = 1
	tiffPhotometricRGB         = 2
)

const (
	// maxTIFFDirectories bounds how many directories a file's chains are walked for.
	maxTIFFDirectories = 64
	// maxTIFFArrayBytes bounds one tag's value, such as a strip offset table.
	maxTIFFArrayBytes = 64 << 20
	// maxTIFFChunkBytes bounds one decoded row or tile, the only part of the
	// source the streaming decoder holds at once.
	maxTIFFChunkBytes = 64 << 20
)

// tiffIFD is one image file directory: the parts of it the large-image path
// needs to pick a directory and stream it.
type tiffIFD struct {
	width, height   int64
	newSubfileType  uint64
	bitsPerSample   []uint64
	samplesPerPixel int
	photometric     int64
	compression     int64
	predictor       int64
	planarConfig    int64
	sampleFormat    []uint64
	extraSamples    []uint64
	rowsPerStrip    int64
	stripOffsets    []uint64
	stripByteCounts []uint64
	tileWidth       int64
	tileLength      int64
	tileOffsets     []uint64
	tileByteCounts  []uint64
	subIFDs         []uint64
}

// tiffLayout is a TIFF's byte order and every directory in IFD0's chain and
// its SubIFDs, IFD0 first.
type tiffLayout struct {
	order binary.ByteOrder
	dirs  []tiffIFD
}

// tiffParser reads directories out of a TIFF held at ra.
type tiffParser struct {
	ra    io.ReaderAt
	size  int64
	order binary.ByteOrder
}

// tiffEntry is one directory entry as stored: its value is inline in raw
// when it fits in four bytes, and at offset otherwise.
type tiffEntry struct {
	typ    uint16
	count  uint32
	raw    [4]byte
	offset uint32
}

// isTIFFHeader reports whether head starts with a TIFF byte-order mark and
// magic number.
func isTIFFHeader(head []byte) bool {
	return len(head) >= 4 && (bytes.Equal(head[:4], []byte("II*\x00")) || bytes.Equal(head[:4], []byte("MM\x00*")))
}

// readTIFFLayout reads the header and walks IFD0's chain and the SubIFDs
// (tag 0x014A) of each directory in it. A broken directory after IFD0 ends
// the walk rather than failing it: IFD0 alone is still an image.
func readTIFFLayout(ra io.ReaderAt, size int64) (*tiffLayout, error) {
	var head [8]byte
	if _, err := ra.ReadAt(head[:], 0); err != nil {
		return nil, fmt.Errorf("tiff header: %w", err)
	}
	p := &tiffParser{ra: ra, size: size}
	switch string(head[:2]) {
	case "II":
		p.order = binary.LittleEndian
	case "MM":
		p.order = binary.BigEndian
	default:
		return nil, errors.New("tiff header: no byte-order mark")
	}
	if p.order.Uint16(head[2:]) != 42 {
		return nil, errors.New("tiff header: not a classic TIFF")
	}

	layout := &tiffLayout{order: p.order}
	seen := map[int64]bool{}
	var walk func(off int64, depth int) error
	walk = func(off int64, depth int) error {
		for off != 0 && len(layout.dirs) < maxTIFFDirectories && !seen[off] {
			seen[off] = true
			ifd, next, err := p.readIFD(off)
			if err != nil {
				return err
			}
			layout.dirs = append(layout.dirs, ifd)
			if depth == 0 {
				for _, sub := range ifd.subIFDs {
					_ = walk(int64(sub), 1)
				}
			}
			off = next
		}
		return nil
	}
	if err := walk(int64(p.order.Uint32(head[4:])), 0); err != nil && len(layout.dirs) == 0 {
		return nil, err
	}
	if len(layout.dirs) == 0 {
		return nil, errors.New("tiff: no image directory")
	}
	return layout, nil
}

// readIFD reads the directory at off and the offset of the next one.
func (p *tiffParser) readIFD(off int64) (tiffIFD, int64, error) {
	var countBuf [2]byte
	if _, err := p.ra.ReadAt(countBuf[:], off); err != nil {
		return tiffIFD{}, 0, fmt.Errorf("tiff directory at %d: %w", off, err)
	}
	n := int64(p.order.Uint16(countBuf[:]))
	buf := make([]byte, n*12+4)
	if _, err := p.ra.ReadAt(buf, off+2); err != nil {
		return tiffIFD{}, 0, fmt.Errorf("tiff directory at %d: %w", off, err)
	}
	entries := make(map[uint16]tiffEntry, n)
	for i := range n {
		e := buf[i*12 : i*12+12]
		entry := tiffEntry{typ: p.order.Uint16(e[2:]), count: p.order.Uint32(e[4:]), offset: p.order.Uint32(e[8:])}
		copy(entry.raw[:], e[8:12])
		entries[p.order.Uint16(e)] = entry
	}
	next := int64(p.order.Uint32(buf[n*12:]))

	ifd := tiffIFD{
		samplesPerPixel: 1,
		compression:     tiffCompressionNone,
		predictor:       1,
		planarConfig:    1,
		photometric:     -1,
	}
	one := func(tag uint16, into *int64) error {
		v, err := p.values(entries, tag)
		if err == nil && len(v) > 0 {
			*into = int64(v[0])
		}
		return err
	}
	list := func(tag uint16, into *[]uint64) error {
		v, err := p.values(entries, tag)
		*into = v
		return err
	}
	var spp int64 = 1
	err := errors.Join(
		one(tiffTagImageWidth, &ifd.width),
		one(tiffTagImageLength, &ifd.height),
		one(tiffTagCompression, &ifd.compression),
		one(tiffTagPhotometric, &ifd.photometric),
		one(tiffTagSamplesPerPixel, &spp),
		one(tiffTagRowsPerStrip, &ifd.rowsPerStrip),
		one(tiffTagPlanarConfig, &ifd.planarConfig),
		one(tiffTagPredictor, &ifd.predictor),
		one(tiffTagTileWidth, &ifd.tileWidth),
		one(tiffTagTileLength, &ifd.tileLength),
		list(tiffTagBitsPerSample, &ifd.bitsPerSample),
		list(tiffTagSampleFormat, &ifd.sampleFormat),
		list(tiffTagExtraSamples, &ifd.extraSamples),
		list(tiffTagStripOffsets, &ifd.stripOffsets),
		list(tiffTagStripByteCounts, &ifd.stripByteCounts),
		list(tiffTagTileOffsets, &ifd.tileOffsets),
		list(tiffTagTileByteCounts, &ifd.tileByteCounts),
		list(tiffTagSubIFDs, &ifd.subIFDs),
	)
	if err != nil {
		return tiffIFD{}, 0, fmt.Errorf("tiff directory at %d: %w", off, err)
	}
	if v, _ := p.values(entries, tiffTagNewSubfileType); len(v) > 0 {
		ifd.newSubfileType = v[0]
	}
	if ifd.width <= 0 || ifd.height <= 0 {
		return tiffIFD{}, 0, fmt.Errorf("tiff directory at %d: no image dimensions", off)
	}
	if spp < 1 || spp > 16 {
		return tiffIFD{}, 0, fmt.Errorf("tiff directory at %d: %d samples per pixel", off, spp)
	}
	ifd.samplesPerPixel = int(spp)
	if len(ifd.bitsPerSample) == 0 {
		ifd.bitsPerSample = []uint64{1}
	}
	if ifd.rowsPerStrip <= 0 || ifd.rowsPerStrip > ifd.height {
		ifd.rowsPerStrip = ifd.height
	}
	return ifd, next, nil
}

// values reads an unsigned integer tag as a list. A missing tag is an empty
// list, not an error.
func (p *tiffParser) values(entries map[uint16]tiffEntry, tag uint16) ([]uint64, error) {
	e, ok := entries[tag]
	if !ok {
		return nil, nil
	}
	var width int64
	switch e.typ {
	case 1, 7: // BYTE, UNDEFINED
		width = 1
	case 3: // SHORT
		width = 2
	case 4, 13: // LONG, IFD
		width = 4
	default:
		return nil, fmt.Errorf("tag %d has type %d", tag, e.typ)
	}
	n := int64(e.count) * width
	if n > maxTIFFArrayBytes || n > p.size {
		return nil, fmt.Errorf("tag %d holds %d bytes", tag, n)
	}
	data := e.raw[:]
	if n > 4 {
		data = make([]byte, n)
		if _, err := p.ra.ReadAt(data, int64(e.offset)); err != nil {
			return nil, fmt.Errorf("tag %d: %w", tag, err)
		}
	}
	out := make([]uint64, e.count)
	for i := range out {
		switch width {
		case 1:
			out[i] = uint64(data[i])
		case 2:
			out[i] = uint64(p.order.Uint16(data[i*2:]))
		default:
			out[i] = uint64(p.order.Uint32(data[i*4:]))
		}
	}
	return out, nil
}

// bits is the directory's sample depth, or 0 when its samples differ.
func (ifd *tiffIFD) bits() uint64 {
	for _, b := range ifd.bitsPerSample[1:] {
		if b != ifd.bitsPerSample[0] {
			return 0
		}
	}
	return ifd.bitsPerSample[0]
}

// decodedBytes is what a full decode of the directory costs: four bytes a
// pixel, or eight when its samples are deeper than 8 bits.
func (ifd *tiffIFD) decodedBytes() int64 {
	perPixel := int64(4)
	for _, b := range ifd.bitsPerSample {
		if b > 8 {
			perPixel = 8
		}
	}
	return ifd.width * ifd.height * perPixel
}

func (ifd *tiffIFD) tiled() bool { return ifd.tileWidth > 0 || ifd.tileLength > 0 }

// unsupported says why the streaming decoder cannot read the directory, or ""
// when it can.
func (ifd *tiffIFD) unsupported() string {
	switch ifd.compression {
	case tiffCompressionNone, tiffCompressionLZW, tiffCompressionDeflate, tiffCompressionDeflateOld, tiffCompressionPackBits:
	case 6, 7:
		return "JPEG compression is not supported"
	default:
		return fmt.Sprintf("compression %d is not supported", ifd.compression)
	}
	if ifd.planarConfig != 1 {
		return "planar configuration 2 (separate planes) is not supported"
	}
	for _, f := range ifd.sampleFormat {
		switch f {
		case 1:
		case 3:
			return "floating-point samples are not supported"
		default:
			return fmt.Sprintf("sample format %d is not supported", f)
		}
	}
	if b := ifd.bits(); b != 8 && b != 16 {
		return fmt.Sprintf("%v bits per sample is not supported", ifd.bitsPerSample)
	}
	if ifd.predictor != 1 && ifd.predictor != 2 {
		return fmt.Sprintf("predictor %d is not supported", ifd.predictor)
	}
	spp := ifd.samplesPerPixel
	switch ifd.photometric {
	case tiffPhotometricWhiteIsZero, tiffPhotometricBlackIsZero:
		if spp != 1 && spp != 2 {
			return fmt.Sprintf("grayscale with %d samples per pixel is not supported", spp)
		}
	case tiffPhotometricRGB:
		if spp != 3 && spp != 4 {
			return fmt.Sprintf("RGB with %d samples per pixel is not supported", spp)
		}
	case 3:
		return "palette color is not supported"
	case 5:
		return "CMYK is not supported"
	case 6:
		return "YCbCr is not supported"
	default:
		return fmt.Sprintf("photometric interpretation %d is not supported", ifd.photometric)
	}
	if ifd.tiled() && (ifd.tileWidth <= 0 || ifd.tileLength <= 0) {
		return "a tiled image needs both tile dimensions"
	}
	if ifd.chunkBytes() > maxTIFFChunkBytes {
		return "a row or tile is too large"
	}
	return ""
}

// chunkBytes is the size of the unit the decoder holds at once: one tile, or
// one row of a strip.
func (ifd *tiffIFD) chunkBytes() int64 {
	sampleBytes := int64(ifd.bits() / 8)
	if ifd.tiled() {
		return ifd.tileWidth * ifd.tileLength * int64(ifd.samplesPerPixel) * sampleBytes
	}
	return ifd.width * int64(ifd.samplesPerPixel) * sampleBytes
}

// largeTIFFSource picks the directory to stream an over-budget TIFF from:
// the largest reduced-resolution directory (NewSubfileType bit 0) that fits
// budget and whose long side is at least longSide, or else IFD0 itself.
func (l *tiffLayout) largeTIFFSource(budget int64, longSide int64) (tiffIFD, error) {
	full := l.dirs[0]
	var best *tiffIFD
	for i := 1; i < len(l.dirs); i++ {
		c := &l.dirs[i]
		if c.newSubfileType&1 == 0 || c.decodedBytes() > budget || max(c.width, c.height) < longSide || c.unsupported() != "" {
			continue
		}
		if best == nil || c.width*c.height > best.width*best.height {
			best = c
		}
	}
	if best != nil {
		return *best, nil
	}
	if reason := full.unsupported(); reason != "" {
		return tiffIFD{}, fmt.Errorf("%w: %d × %d TIFF: %s", ErrImageTooLarge, full.width, full.height, reason)
	}
	if full.width*full.height > MaxStreamedPixels {
		return tiffIFD{}, fmt.Errorf("%w: %d × %d TIFF is over %d pixels", ErrImageTooLarge, full.width, full.height, MaxStreamedPixels)
	}
	return full, nil
}

// decodeTIFFStreamed decodes ifd one row (strips) or one tile at a time and
// box-filters it into an image whose long side is at most longSide. It holds
// the output, one row or tile, and the few output rows still being summed;
// never the whole source.
func decodeTIFFStreamed(ra io.ReaderAt, order binary.ByteOrder, ifd tiffIFD, longSide int64) (image.Image, error) {
	if reason := ifd.unsupported(); reason != "" {
		return nil, fmt.Errorf("tiff: %s", reason)
	}
	outW, outH := ifd.width, ifd.height
	if long := max(outW, outH); long > longSide {
		outW = max(1, ifd.width*longSide/long)
		outH = max(1, ifd.height*longSide/long)
	}
	assoc := len(ifd.extraSamples) > 0 && ifd.extraSamples[0] == 1
	sink := newBoxSink(ifd.width, ifd.height, outW, outH, ifd.samplesPerPixel, assoc)
	s := &tiffStream{ra: ra, order: order, ifd: ifd, sink: sink, sampleBytes: int(ifd.bits() / 8)}
	var err error
	if ifd.tiled() {
		err = s.readTiles()
	} else {
		err = s.readStrips()
	}
	if err != nil {
		return nil, fmt.Errorf("tiff: %w", err)
	}
	return sink.out, nil
}

// tiffStream carries one streamed decode.
type tiffStream struct {
	ra          io.ReaderAt
	order       binary.ByteOrder
	ifd         tiffIFD
	sink        *boxSink
	sampleBytes int
	zr          io.ReadCloser
}

func (s *tiffStream) readStrips() error {
	ifd := s.ifd
	strips := (ifd.height + ifd.rowsPerStrip - 1) / ifd.rowsPerStrip
	if int64(len(ifd.stripOffsets)) < strips || int64(len(ifd.stripByteCounts)) < strips {
		return fmt.Errorf("%d strips listed, %d needed", min(len(ifd.stripOffsets), len(ifd.stripByteCounts)), strips)
	}
	row := make([]byte, ifd.chunkBytes())
	for i := range strips {
		r, err := s.open(ifd.stripOffsets[i], ifd.stripByteCounts[i])
		if err != nil {
			return err
		}
		end := min((i+1)*ifd.rowsPerStrip, ifd.height)
		for y := i * ifd.rowsPerStrip; y < end; y++ {
			if _, err := io.ReadFull(r, row); err != nil {
				return fmt.Errorf("strip %d row %d: %w", i, y, err)
			}
			s.undoPredictor(row)
			s.sink.addSpan(y, 0, row, ifd.width, s.sampleBytes, s.order, ifd.photometric == tiffPhotometricWhiteIsZero)
		}
		s.sink.finishRows(end)
	}
	return nil
}

func (s *tiffStream) readTiles() error {
	ifd := s.ifd
	across := (ifd.width + ifd.tileWidth - 1) / ifd.tileWidth
	down := (ifd.height + ifd.tileLength - 1) / ifd.tileLength
	if int64(len(ifd.tileOffsets)) < across*down || int64(len(ifd.tileByteCounts)) < across*down {
		return fmt.Errorf("%d tiles listed, %d needed", min(len(ifd.tileOffsets), len(ifd.tileByteCounts)), across*down)
	}
	tile := make([]byte, ifd.chunkBytes())
	rowBytes := ifd.tileWidth * int64(ifd.samplesPerPixel) * int64(s.sampleBytes)
	for ty := range down {
		for tx := range across {
			i := ty*across + tx
			r, err := s.open(ifd.tileOffsets[i], ifd.tileByteCounts[i])
			if err != nil {
				return err
			}
			if _, err := io.ReadFull(r, tile); err != nil {
				return fmt.Errorf("tile %d: %w", i, err)
			}
			x0 := tx * ifd.tileWidth
			span := min(ifd.tileWidth, ifd.width-x0)
			for ry := range ifd.tileLength {
				y := ty*ifd.tileLength + ry
				if y >= ifd.height {
					break
				}
				row := tile[ry*rowBytes : (ry+1)*rowBytes]
				s.undoPredictor(row)
				s.sink.addSpan(y, x0, row, span, s.sampleBytes, s.order, ifd.photometric == tiffPhotometricWhiteIsZero)
			}
		}
		s.sink.finishRows(min((ty+1)*ifd.tileLength, ifd.height))
	}
	return nil
}

// open returns the decompressed bytes of the strip or tile stored at off.
func (s *tiffStream) open(off, n uint64) (io.Reader, error) {
	section := io.NewSectionReader(s.ra, int64(off), int64(n))
	switch s.ifd.compression {
	case tiffCompressionLZW:
		return lzw.NewReader(section, lzw.MSB, 8), nil
	case tiffCompressionDeflate, tiffCompressionDeflateOld:
		if s.zr == nil {
			zr, err := zlib.NewReader(section)
			if err != nil {
				return nil, fmt.Errorf("deflate: %w", err)
			}
			s.zr = zr
			return zr, nil
		}
		if err := s.zr.(zlib.Resetter).Reset(section, nil); err != nil {
			return nil, fmt.Errorf("deflate: %w", err)
		}
		return s.zr, nil
	case tiffCompressionPackBits:
		return &packBitsReader{r: bufio.NewReader(section)}, nil
	default:
		return section, nil
	}
}

// undoPredictor reverses horizontal differencing (predictor 2) on one row.
func (s *tiffStream) undoPredictor(row []byte) {
	if s.ifd.predictor != 2 {
		return
	}
	ch := s.ifd.samplesPerPixel
	if s.sampleBytes == 1 {
		for i := ch; i < len(row); i++ {
			row[i] += row[i-ch]
		}
		return
	}
	for i := ch; i < len(row)/2; i++ {
		s.order.PutUint16(row[i*2:], s.order.Uint16(row[i*2:])+s.order.Uint16(row[(i-ch)*2:]))
	}
}

// packBitsReader decodes a PackBits stream: a header byte n, then n+1
// literal bytes when n is 0–127, or one byte repeated 1-n times when n is
// -127 to -1. -128 is a no-op.
type packBitsReader struct {
	r       *bufio.Reader
	literal int
	repeat  int
	b       byte
}

func (p *packBitsReader) Read(out []byte) (int, error) {
	n := 0
	for n < len(out) {
		switch {
		case p.literal > 0:
			k, err := io.ReadFull(p.r, out[n:n+min(p.literal, len(out)-n)])
			n += k
			p.literal -= k
			if err != nil {
				return n, err
			}
		case p.repeat > 0:
			k := min(p.repeat, len(out)-n)
			for i := range k {
				out[n+i] = p.b
			}
			n += k
			p.repeat -= k
		default:
			h, err := p.r.ReadByte()
			if err != nil {
				return n, err
			}
			switch hdr := int8(h); {
			case hdr >= 0:
				p.literal = int(hdr) + 1
			case hdr != -128:
				if p.b, err = p.r.ReadByte(); err != nil {
					return n, err
				}
				p.repeat = 1 - int(hdr)
			}
		}
	}
	return n, nil
}

// boxSink averages source pixels into an output image, each output pixel the
// mean of the block of source pixels that maps onto it. Source rows arrive in
// order, in spans; only the output rows still being summed are held.
type boxSink struct {
	srcW, srcH, outW, outH int64
	ch                     int
	// pending holds the sums for output rows base, base+1, ….
	pending [][]uint64
	free    [][]uint64
	base    int64
	out     image.Image
	// is16 is set from the first span: samples are scaled down at flush.
	is16 bool
}

func newBoxSink(srcW, srcH, outW, outH int64, ch int, assoc bool) *boxSink {
	b := &boxSink{srcW: srcW, srcH: srcH, outW: outW, outH: outH, ch: ch}
	rect := image.Rect(0, 0, int(outW), int(outH))
	switch {
	case ch == 1:
		b.out = image.NewGray(rect)
	case ch == 3 || assoc:
		b.out = image.NewRGBA(rect)
	default:
		b.out = image.NewNRGBA(rect)
	}
	return b
}

// rowStart is the first source row that maps onto output row oy.
func (b *boxSink) rowStart(oy int64) int64 { return (oy*b.srcH + b.outH - 1) / b.outH }

// colStart is the first source column that maps onto output column ox.
func (b *boxSink) colStart(ox int64) int64 { return (ox*b.srcW + b.outW - 1) / b.outW }

// row returns the sums for output row oy, starting it if it is new.
func (b *boxSink) row(oy int64) []uint64 {
	for int64(len(b.pending)) <= oy-b.base {
		var r []uint64
		if n := len(b.free); n > 0 {
			r = b.free[n-1]
			b.free = b.free[:n-1]
			clear(r)
		} else {
			r = make([]uint64, b.outW*int64(b.ch))
		}
		b.pending = append(b.pending, r)
	}
	return b.pending[oy-b.base]
}

// addSpan adds count pixels of source row y, starting at column x0, from
// samples stored at sampleBytes each in order.
func (b *boxSink) addSpan(y, x0 int64, samples []byte, count int64, sampleBytes int, order binary.ByteOrder, invert bool) {
	b.is16 = sampleBytes == 2
	sums := b.row(y * b.outH / b.srcH)
	ch := int64(b.ch)
	var maxV uint64 = 255
	if b.is16 {
		maxV = 65535
	}
	for i := range count {
		o := (x0 + i) * b.outW / b.srcW * ch
		for c := range ch {
			var v uint64
			if sampleBytes == 1 {
				v = uint64(samples[i*ch+c])
			} else {
				v = uint64(order.Uint16(samples[(i*ch+c)*2:]))
			}
			if invert && c == 0 {
				v = maxV - v
			}
			sums[o+c] += v
		}
	}
}

// finishRows writes out every output row whose source rows all come before
// srcEnd.
func (b *boxSink) finishRows(srcEnd int64) {
	for len(b.pending) > 0 {
		if next := b.rowStart(b.base + 1); next > srcEnd {
			return
		}
		b.flush(b.base, b.pending[0])
		b.free = append(b.free, b.pending[0])
		b.pending = b.pending[1:]
		b.base++
	}
}

// flush writes the averages of output row oy into the output image.
func (b *boxSink) flush(oy int64, sums []uint64) {
	rows := uint64(b.rowStart(oy+1) - b.rowStart(oy))
	ch := int64(b.ch)
	var shift uint
	if b.is16 {
		shift = 8
	}
	px := make([]uint8, 4)
	for ox := range b.outW {
		n := rows * uint64(b.colStart(ox+1)-b.colStart(ox))
		for c := range ch {
			px[c] = uint8(sums[ox*ch+c] / n >> shift)
		}
		switch img := b.out.(type) {
		case *image.Gray:
			img.Pix[oy*int64(img.Stride)+ox] = px[0]
		case *image.RGBA:
			copy(img.Pix[oy*int64(img.Stride)+ox*4:], expand(px, b.ch))
		case *image.NRGBA:
			copy(img.Pix[oy*int64(img.Stride)+ox*4:], expand(px, b.ch))
		}
	}
}

// expand turns gray, gray+alpha, RGB or RGBA samples into RGBA in place.
func expand(px []uint8, ch int) []uint8 {
	switch ch {
	case 2:
		px[3], px[1], px[2] = px[1], px[0], px[0]
	case 3:
		px[3] = 255
	}
	return px
}
