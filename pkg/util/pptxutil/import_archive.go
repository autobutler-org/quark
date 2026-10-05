package pptxutil

// cspell:ignore EOCD

import (
	"archive/zip"
	"encoding/binary"
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"net/url"
	"path"
	"strings"
)

// The end of a zip: the end-of-central-directory record and, for an archive
// past 65,535 entries or 4 GiB, the zip64 record a locator before it points at.
const (
	eocdSignature       = 0x06054b50
	eocdLength          = 22
	zip64LocatorSig     = 0x07064b50
	zip64LocatorLength  = 20
	zip64EOCDSignature  = 0x06064b50
	zip64EOCDLength     = 56
	maxZipCommentLength = 0xFFFF
)

// pptxArchive is an opened .pptx: its parts by lowercased name, since OPC part
// names are case-insensitive, and what is left of the read budget.
type pptxArchive struct {
	parts map[string]*zip.File
	// remaining is how many uncompressed bytes the import may still read,
	// over every part together.
	remaining int64
}

// openArchive checks the zip's directory against the entry limits before
// archive/zip reads a byte of it, then indexes the parts. A name that could
// climb out of the package, or that two entries share, refuses the archive.
func openArchive(src io.ReaderAt, size int64) (*pptxArchive, error) {
	if size <= 0 {
		return nil, fmt.Errorf("%w: the file is empty", ErrNotPptx)
	}
	entries, dirSize, err := zipDirectory(src, size)
	if err != nil {
		return nil, err
	}
	if entries > MaxImportEntries {
		return nil, fmt.Errorf("%w: the package holds more than %d entries", ErrTooLarge, MaxImportEntries)
	}
	if dirSize > maxCentralDirectoryBytes {
		return nil, fmt.Errorf("%w: the package's directory is larger than %d bytes", ErrTooLarge, maxCentralDirectoryBytes)
	}
	zr, err := zip.NewReader(src, size)
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrNotPptx, err)
	}
	if len(zr.File) > MaxImportEntries {
		return nil, fmt.Errorf("%w: the package holds more than %d entries", ErrTooLarge, MaxImportEntries)
	}
	a := &pptxArchive{parts: make(map[string]*zip.File, len(zr.File)), remaining: MaxImportBytes}
	for _, f := range zr.File {
		if !safePartName(f.Name) {
			return nil, fmt.Errorf("%w: entry %q names a path outside the package", ErrNotPptx, f.Name)
		}
		key := strings.ToLower(f.Name)
		if _, dup := a.parts[key]; dup {
			return nil, fmt.Errorf("%w: entry %q appears twice", ErrNotPptx, f.Name)
		}
		a.parts[key] = f
	}
	return a, nil
}

// zipDirectory reads the entry count and central directory size from the end
// of the archive, following the zip64 locator when the plain record defers to
// it.
func zipDirectory(src io.ReaderAt, size int64) (entries, dirSize uint64, err error) {
	tailLen := min(size, eocdLength+maxZipCommentLength)
	tail := make([]byte, tailLen)
	if _, err := src.ReadAt(tail, size-tailLen); err != nil && !errors.Is(err, io.EOF) {
		return 0, 0, err
	}
	at := -1
	for i := len(tail) - eocdLength; i >= 0; i-- {
		if binary.LittleEndian.Uint32(tail[i:]) == eocdSignature {
			at = i
			break
		}
	}
	if at < 0 {
		return 0, 0, fmt.Errorf("%w: not a zip archive", ErrNotPptx)
	}
	eocd := tail[at:]
	entries = uint64(binary.LittleEndian.Uint16(eocd[10:]))
	dirSize = uint64(binary.LittleEndian.Uint32(eocd[12:]))
	if entries != 0xFFFF && dirSize != 0xFFFFFFFF {
		return entries, dirSize, nil
	}

	eocdOffset := size - tailLen + int64(at)
	if eocdOffset < zip64LocatorLength {
		return 0, 0, fmt.Errorf("%w: a zip64 archive without its locator", ErrNotPptx)
	}
	locator := make([]byte, zip64LocatorLength)
	if _, err := src.ReadAt(locator, eocdOffset-zip64LocatorLength); err != nil {
		return 0, 0, fmt.Errorf("%w: %v", ErrNotPptx, err)
	}
	if binary.LittleEndian.Uint32(locator) != zip64LocatorSig {
		return 0, 0, fmt.Errorf("%w: a zip64 archive without its locator", ErrNotPptx)
	}
	recordOffset := binary.LittleEndian.Uint64(locator[8:])
	if recordOffset > uint64(size-zip64EOCDLength) {
		return 0, 0, fmt.Errorf("%w: the zip64 record lies outside the file", ErrNotPptx)
	}
	record := make([]byte, zip64EOCDLength)
	if _, err := src.ReadAt(record, int64(recordOffset)); err != nil {
		return 0, 0, fmt.Errorf("%w: %v", ErrNotPptx, err)
	}
	if binary.LittleEndian.Uint32(record) != zip64EOCDSignature {
		return 0, 0, fmt.Errorf("%w: the zip64 record is missing", ErrNotPptx)
	}
	return binary.LittleEndian.Uint64(record[32:]), binary.LittleEndian.Uint64(record[40:]), nil
}

// safePartName reports whether a zip entry name stays inside the package: a
// relative, forward-slash path with no "." or ".." segment and nothing a
// filesystem would read as a drive or a device.
func safePartName(name string) bool {
	if name == "" || len(name) > 1024 || strings.ContainsAny(name, "\\:\x00") || strings.HasPrefix(name, "/") {
		return false
	}
	for _, seg := range strings.Split(strings.TrimSuffix(name, "/"), "/") {
		if seg == "" || seg == "." || seg == ".." {
			return false
		}
	}
	return true
}

// has reports whether the package holds the part.
func (a *pptxArchive) has(name string) bool {
	_, ok := a.parts[strings.ToLower(name)]
	return ok
}

// open opens a part for reading, its bytes charged against the import's
// budget and capped at limit. Reading past either is [ErrTooLarge], whatever
// size the entry declares.
func (a *pptxArchive) open(name string, limit int64) (io.ReadCloser, error) {
	f, ok := a.parts[strings.ToLower(name)]
	if !ok {
		return nil, fmt.Errorf("%w: %s", errMissingPart, name)
	}
	rc, err := f.Open()
	if err != nil {
		return nil, fmt.Errorf("%w: %s: %v", ErrNotPptx, name, err)
	}
	return &budgetReader{rc: rc, archive: a, name: name, limit: limit}, nil
}

// decodeXML decodes a part into v; see decodeXMLCounted.
func (a *pptxArchive) decodeXML(name string, v any) error {
	_, err := a.decodeXMLCounted(name, v)
	return err
}

// decodeXMLCounted decodes a part into v and returns how many elements it
// held, refusing one past [MaxXMLPartBytes], [MaxXMLElements] or
// [MaxXMLDepth]. The element cap is what bounds the memory v costs, since a
// part's size alone does not: a few bytes per element add up to millions of
// them. encoding/xml expands no entities a document declares, so a part
// cannot grow past what it holds.
func (a *pptxArchive) decodeXMLCounted(name string, v any) (int, error) {
	rc, err := a.open(name, MaxXMLPartBytes)
	if err != nil {
		return 0, err
	}
	defer rc.Close()
	limiter := &tokenLimiter{dec: xml.NewDecoder(rc)}
	if err := xml.NewTokenDecoder(limiter).Decode(v); err != nil {
		if errors.Is(err, ErrTooLarge) {
			return limiter.elements, err
		}
		return limiter.elements, fmt.Errorf("%w: %s: %v", ErrNotPptx, name, err)
	}
	return limiter.elements, nil
}

// errMissingPart is a part the package does not hold.
var errMissingPart = errors.New("pptxutil: missing part")

// budgetReader reads one part, counting what it reads against its own limit
// and the archive's remaining budget. A byte past either is never handed
// out: the read that would need it fails instead, and says which was passed.
type budgetReader struct {
	rc      io.ReadCloser
	archive *pptxArchive
	name    string
	limit   int64
	read    int64
	// pastLimit and pastBudget record which cap a read ran into.
	pastLimit, pastBudget bool
}

func (b *budgetReader) Read(p []byte) (int, error) {
	allow := min(b.limit-b.read, b.archive.remaining)
	if allow <= 0 {
		// One byte more is what tells a part that is too large from one
		// that fills its cap exactly.
		var probe [1]byte
		if n, _ := b.rc.Read(probe[:]); n == 0 {
			return 0, io.EOF
		}
		if b.archive.remaining <= 0 {
			b.pastBudget = true
			return 0, fmt.Errorf("%w: the package unpacks to more than %d bytes", ErrTooLarge, int64(MaxImportBytes))
		}
		b.pastLimit = true
		return 0, fmt.Errorf("%w: %s is larger than %d bytes", ErrTooLarge, b.name, b.limit)
	}
	if int64(len(p)) > allow {
		p = p[:allow]
	}
	n, err := b.rc.Read(p)
	b.read += int64(n)
	b.archive.remaining -= int64(n)
	return n, err
}

func (b *budgetReader) Close() error { return b.rc.Close() }

// tokenLimiter passes tokens through and fails once a part holds more than
// [MaxXMLElements] elements or nests them deeper than [MaxXMLDepth]. Tokens
// are copied, since the decoder reuses their bytes.
type tokenLimiter struct {
	dec      *xml.Decoder
	depth    int
	elements int
}

func (d *tokenLimiter) Token() (xml.Token, error) {
	tok, err := d.dec.Token()
	if err != nil {
		return nil, err
	}
	switch tok.(type) {
	case xml.StartElement:
		d.depth++
		d.elements++
		if d.depth > MaxXMLDepth {
			return nil, fmt.Errorf("%w: XML nests more than %d elements deep", ErrTooLarge, MaxXMLDepth)
		}
		if d.elements > MaxXMLElements {
			return nil, fmt.Errorf("%w: a part holds more than %d XML elements", ErrTooLarge, MaxXMLElements)
		}
	case xml.EndElement:
		d.depth--
	}
	return xml.CopyToken(tok), nil
}

// resolveTarget resolves a relationship target against the part that holds
// it; an absolute target is from the package root. A target that climbs out
// of the package resolves to nothing.
func resolveTarget(source, target string) (string, bool) {
	if unescaped, err := url.PathUnescape(target); err == nil {
		target = unescaped
	}
	if target == "" || strings.ContainsAny(target, "\\\x00") {
		return "", false
	}
	var kept []string
	if dir := path.Dir(source); !strings.HasPrefix(target, "/") && dir != "." {
		kept = strings.Split(dir, "/")
	}
	for _, seg := range strings.Split(target, "/") {
		switch seg {
		case "", ".":
		case "..":
			if len(kept) == 0 {
				return "", false
			}
			kept = kept[:len(kept)-1]
		default:
			kept = append(kept, seg)
		}
	}
	if len(kept) == 0 {
		return "", false
	}
	return strings.Join(kept, "/"), true
}

// relsPath is the relationships part of a part.
func relsPath(part string) string {
	return path.Join(path.Dir(part), "_rels", path.Base(part)+".rels")
}
