package xlsutil_test

// cspell:ignore DIFAT Fmla ifmt

import (
	"bytes"
	"encoding/binary"
	"math"
	"unicode/utf16"
)

// The tests build their workbooks in code: a minimal BIFF8 record stream
// wrapped in a minimal version 3 compound file. Building rather than checking
// in binaries is what lets a test name the one record it is about, and lets
// the hostile cases break exactly one thing.

const (
	sectorSize = 512
	endOfChain = 0xFFFFFFFE
	fatSect    = 0xFFFFFFFD
	freeSect   = 0xFFFFFFFF
	// miniCutoff is the size below which a stream lives in the mini stream.
	// Built streams are padded past it so they sit in regular sectors; the
	// LibreOffice fixture covers the mini stream.
	miniCutoff = 4096
)

// cfbStream is one named stream of a compound file.
type cfbStream struct {
	name string
	data []byte
	// sizeOverride makes the directory state declaredSize rather than the
	// stream's real length.
	sizeOverride bool
	declaredSize uint32
	// loop makes the stream's last sector chain back to its first, the
	// classic cyclic-FAT attack.
	loop bool
}

// buildCFB lays out header, FAT, directory, then each stream's sectors.
func buildCFB(streams ...cfbStream) []byte {
	padded := make([][]byte, len(streams))
	sectorsFor := func(n int) int { return (n + sectorSize - 1) / sectorSize }
	dataSectors := 0
	for i, s := range streams {
		b := s.data
		if len(b) < miniCutoff {
			b = append(append([]byte(nil), b...), make([]byte, miniCutoff-len(b))...)
		}
		padded[i] = b
		dataSectors += sectorsFor(len(b))
	}
	dirSectors := sectorsFor((len(streams) + 1) * 128)
	fatSectors := 1
	for fatSectors*sectorSize/4 < fatSectors+dirSectors+dataSectors {
		fatSectors++
	}
	if fatSectors > 109 {
		panic("buildCFB: stream too large for a header-only DIFAT")
	}
	total := fatSectors + dirSectors + dataSectors

	fat := make([]uint32, fatSectors*sectorSize/4)
	for i := range fat {
		fat[i] = freeSect
	}
	for i := 0; i < fatSectors; i++ {
		fat[i] = fatSect
	}
	chain := func(start, n int, loop bool) {
		for i := 0; i < n-1; i++ {
			fat[start+i] = uint32(start + i + 1)
		}
		fat[start+n-1] = endOfChain
		if loop {
			fat[start+n-1] = uint32(start)
		}
	}
	dirStart := fatSectors
	chain(dirStart, dirSectors, false)

	dir := make([]byte, dirSectors*sectorSize)
	entry := func(i int, name string, typ byte, child, right uint32, start uint32, size uint32) {
		e := dir[i*128 : (i+1)*128]
		units := utf16.Encode([]rune(name))
		for j, u := range units {
			binary.LittleEndian.PutUint16(e[2*j:], u)
		}
		binary.LittleEndian.PutUint16(e[64:], uint16(2*len(units)+2))
		e[66] = typ
		e[67] = 1 // black
		binary.LittleEndian.PutUint32(e[68:], freeSect)
		binary.LittleEndian.PutUint32(e[72:], right)
		binary.LittleEndian.PutUint32(e[76:], child)
		binary.LittleEndian.PutUint32(e[116:], start)
		binary.LittleEndian.PutUint32(e[120:], size)
	}
	entry(0, "Root Entry", 5, 1, freeSect, endOfChain, 0)

	next := dirStart + dirSectors
	for i, s := range streams {
		n := sectorsFor(len(padded[i]))
		chain(next, n, s.loop)
		right := uint32(freeSect)
		if i+1 < len(streams) {
			right = uint32(i + 2)
		}
		size := uint32(len(padded[i]))
		if s.sizeOverride {
			size = s.declaredSize
		}
		entry(i+1, s.name, 2, freeSect, right, uint32(next), size)
		next += n
	}

	header := make([]byte, sectorSize)
	copy(header, []byte{0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1})
	binary.LittleEndian.PutUint16(header[24:], 0x003E)
	binary.LittleEndian.PutUint16(header[26:], 3)
	binary.LittleEndian.PutUint16(header[28:], 0xFFFE)
	binary.LittleEndian.PutUint16(header[30:], 9)
	binary.LittleEndian.PutUint16(header[32:], 6)
	binary.LittleEndian.PutUint32(header[44:], uint32(fatSectors))
	binary.LittleEndian.PutUint32(header[48:], uint32(dirStart))
	binary.LittleEndian.PutUint32(header[56:], miniCutoff)
	binary.LittleEndian.PutUint32(header[60:], endOfChain)
	binary.LittleEndian.PutUint32(header[68:], endOfChain)
	for i := 0; i < 109; i++ {
		v := uint32(freeSect)
		if i < fatSectors {
			v = uint32(i)
		}
		binary.LittleEndian.PutUint32(header[76+4*i:], v)
	}

	var out bytes.Buffer
	out.Write(header)
	for _, v := range fat {
		_ = binary.Write(&out, binary.LittleEndian, v)
	}
	out.Write(dir)
	for _, b := range padded {
		out.Write(b)
		out.Write(make([]byte, sectorsFor(len(b))*sectorSize-len(b)))
	}
	if out.Len() != (total+1)*sectorSize {
		panic("buildCFB: layout arithmetic is wrong")
	}
	return out.Bytes()
}

// xls wraps a Workbook stream in a compound file.
func xls(stream []byte) []byte {
	return buildCFB(cfbStream{name: "Workbook", data: stream})
}

// rec is one BIFF record: a type, a length, and the body built from parts,
// each written little-endian.
func rec(typ uint16, parts ...any) []byte {
	var body bytes.Buffer
	for _, p := range parts {
		switch v := p.(type) {
		case []byte:
			body.Write(v)
		case string:
			body.WriteString(v)
		default:
			if err := binary.Write(&body, binary.LittleEndian, v); err != nil {
				panic(err)
			}
		}
	}
	return rawRec(typ, uint16(body.Len()), body.Bytes())
}

// rawRec writes a record whose stated length need not match its body.
func rawRec(typ, length uint16, body []byte) []byte {
	out := make([]byte, 4, 4+len(body))
	binary.LittleEndian.PutUint16(out, typ)
	binary.LittleEndian.PutUint16(out[2:], length)
	return append(out, body...)
}

const (
	tFormula    = 0x0006
	tEOF        = 0x000A
	tDateMode   = 0x0022
	tFilePass   = 0x002F
	tContinue   = 0x003C
	tBoundSheet = 0x0085
	tMulRK      = 0x00BD
	tXF         = 0x00E0
	tSST        = 0x00FC
	tLabelSST   = 0x00FD
	tNumber     = 0x0203
	tLabel      = 0x0204
	tBoolErr    = 0x0205
	tString     = 0x0207
	tRK         = 0x027E
	tFormat     = 0x041E
	tBOF        = 0x0809
	tShrFmla    = 0x04BC
	tDimensions = 0x0200
)

// bof opens a substream: 0x0005 globals, 0x0010 worksheet, 0x0020 chart.
func bof(dt uint16) []byte {
	return rec(tBOF, uint16(0x0600), dt, uint16(0x0DBB), uint16(0x07CC), uint32(0), uint32(0x06))
}

func eof() []byte { return rec(tEOF) }

// compressed is a 16-bit-counted XLUnicodeString in one byte a character.
func compressed(s string) []byte {
	out := []byte{byte(len(s)), byte(len(s) >> 8), 0}
	return append(out, s...)
}

// wide is the same string in two bytes a character.
func wide(s string) []byte {
	units := utf16.Encode([]rune(s))
	out := []byte{byte(len(units)), byte(len(units) >> 8), 1}
	for _, u := range units {
		out = append(out, byte(u), byte(u>>8))
	}
	return out
}

// sst is a one-record shared string table of compressed strings.
func sst(strs ...string) []byte {
	parts := []any{uint32(len(strs)), uint32(len(strs))}
	for _, s := range strs {
		parts = append(parts, compressed(s))
	}
	return rec(tSST, parts...)
}

// xf is an XF record whose number format is ifmt; the rest is zeros.
func xf(ifmt uint16) []byte {
	return rec(tXF, uint16(0), ifmt, make([]byte, 16))
}

func number(row, col, xfIndex uint16, v float64) []byte {
	return rec(tNumber, row, col, xfIndex, math.Float64bits(v))
}

func labelSST(row, col, i uint16) []byte {
	return rec(tLabelSST, row, col, uint16(0), uint32(i))
}

// formula is a FORMULA record whose cached result is the 8 bytes given.
func formula(row, col uint16, result []byte) []byte {
	return rec(tFormula, row, col, uint16(0), result, uint16(0), uint32(0), uint16(0))
}

// special is a formula result that is not a number: 0 string, 1 boolean,
// 2 error, 3 empty string.
func special(kind, value byte) []byte {
	return []byte{kind, 0, value, 0, 0, 0, 0xFF, 0xFF}
}

func numberResult(v float64) []byte {
	return binary.LittleEndian.AppendUint64(nil, math.Float64bits(v))
}

// sheetSrc is one BOUNDSHEET and, for a worksheet, the cell records of its
// substream, which stream() wraps in BOF and EOF.
type sheetSrc struct {
	name  string
	dt    byte
	cells [][]byte
	// raw replaces the whole substream, BOF and EOF included.
	raw []byte
	// offset, when set, replaces the computed BOF offset.
	offset *uint32
}

// book is a workbook to build: global records before the sheet list, the
// sheets, and global records after it (the SST, by Excel's order).
type book struct {
	pre    [][]byte
	sheets []sheetSrc
	post   [][]byte
}

// stream lays the workbook out: globals, then each sheet substream at the
// offset its BOUNDSHEET names.
func (b book) stream() []byte {
	bodies := make([][]byte, len(b.sheets))
	for i, s := range b.sheets {
		if s.raw != nil {
			bodies[i] = s.raw
			continue
		}
		body := bof(0x0010)
		for _, c := range s.cells {
			body = append(body, c...)
		}
		bodies[i] = append(body, eof()...)
	}

	globals := func(offsets []uint32) []byte {
		out := bof(0x0005)
		for _, r := range b.pre {
			out = append(out, r...)
		}
		for i, s := range b.sheets {
			name := []byte{byte(len(s.name)), 0}
			name = append(name, s.name...)
			out = append(out, rec(tBoundSheet, offsets[i], byte(0), s.dt, name)...)
		}
		for _, r := range b.post {
			out = append(out, r...)
		}
		return append(out, eof()...)
	}

	offsets := make([]uint32, len(b.sheets))
	at := uint32(len(globals(offsets)))
	for i, s := range b.sheets {
		offsets[i] = at
		if s.offset != nil {
			offsets[i] = *s.offset
		}
		at += uint32(len(bodies[i]))
	}
	out := globals(offsets)
	for _, body := range bodies {
		out = append(out, body...)
	}
	return out
}

// oneSheet is a workbook of one worksheet holding cells, with the given
// shared strings.
func oneSheet(shared []string, cells ...[]byte) []byte {
	return xls(book{
		sheets: []sheetSrc{{name: "Sheet1", cells: cells}},
		post:   [][]byte{sst(shared...)},
	}.stream())
}
