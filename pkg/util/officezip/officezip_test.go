package officezip_test

import (
	"archive/zip"
	"bytes"
	"compress/flate"
	"encoding/xml"
	"errors"
	"io"
	"runtime"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/officezip"
)

// entry is one file of a test zip.
type entry struct {
	name, body string
}

// buildZip writes the entries into a zip, deflated.
func buildZip(t testing.TB, entries ...entry) []byte {
	t.Helper()
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	for _, e := range entries {
		w, err := zw.Create(e.name)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := io.WriteString(w, e.body); err != nil {
			t.Fatal(err)
		}
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

// open opens a zip held in memory.
func open(t testing.TB, data []byte, limits officezip.Limits) (*officezip.Package, error) {
	t.Helper()
	return officezip.Open(bytes.NewReader(data), int64(len(data)), limits)
}

// mustOpen opens a zip held in memory and fails the test if it cannot.
func mustOpen(t testing.TB, data []byte, limits officezip.Limits) *officezip.Package {
	t.Helper()
	pkg, err := open(t, data, limits)
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	return pkg
}

// readPart reads a whole part.
func readPart(pkg *officezip.Package, name string) (string, error) {
	rc, err := pkg.Part(name)
	if err != nil {
		return "", err
	}
	defer rc.Close()
	var sb strings.Builder
	_, err = io.Copy(&sb, rc)
	return sb.String(), err
}

// allocated reports how many bytes fn allocates on the heap.
func allocated(fn func()) uint64 {
	runtime.GC()
	var before, after runtime.MemStats
	runtime.ReadMemStats(&before)
	fn()
	runtime.ReadMemStats(&after)
	return after.TotalAlloc - before.TotalAlloc
}

const docxDocument = `<?xml version="1.0" encoding="UTF-8"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
<w:body><w:p><w:r><w:t>Hello</w:t></w:r></w:p><w:p><w:r><w:t>World</w:t></w:r></w:p></w:body>
</w:document>`

const packageRels = `<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>`

const documentRels = `<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/image1.png"/>
<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" Target="https://example.com/" TargetMode="External"/>
<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/attachedTemplate" Target="file:///C:/evil.dotm" TargetMode="External"/>
<Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../../../etc/passwd"/>
<Relationship Id="rId5" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="/word/styles.xml"/>
</Relationships>`

const odtManifest = `<?xml version="1.0" encoding="UTF-8"?>
<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.3">
<manifest:file-entry manifest:full-path="/" manifest:media-type="application/vnd.oasis.opendocument.text"/>
<manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>
<manifest:file-entry manifest:full-path="Pictures/a.png" manifest:media-type="image/png">
<manifest:encryption-data manifest:checksum-type="SHA1/1K" manifest:checksum="abc"/>
</manifest:file-entry>
</manifest:manifest>`

// docx is a small but well-formed word-processing package.
func docx(t testing.TB) []byte {
	return buildZip(t,
		entry{"[Content_Types].xml", `<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>`},
		entry{"_rels/.rels", packageRels},
		entry{"word/document.xml", docxDocument},
		entry{"word/_rels/document.xml.rels", documentRels},
		entry{"word/media/image1.png", "\x89PNG"},
	)
}

func TestOpenListsAndReadsParts(t *testing.T) {
	pkg := mustOpen(t, docx(t), officezip.Limits{})
	if got := pkg.Names(); len(got) != 5 || got[2] != "word/document.xml" {
		t.Fatalf("Names() = %v", got)
	}
	if !pkg.Has("WORD/Document.xml") {
		t.Error("Has ignores case: WORD/Document.xml should be found")
	}
	if pkg.Has("word/missing.xml") {
		t.Error("Has(word/missing.xml) = true")
	}
	got, err := readPart(pkg, "Word/Media/Image1.PNG")
	if err != nil || got != "\x89PNG" {
		t.Fatalf("Part = %q, %v", got, err)
	}
}

func TestPartMissing(t *testing.T) {
	pkg := mustOpen(t, docx(t), officezip.Limits{})
	if _, err := pkg.Part("word/styles.xml"); !errors.Is(err, officezip.ErrMissingPart) {
		t.Fatalf("Part(missing) err = %v, want ErrMissingPart", err)
	}
	if _, err := pkg.XML("word/styles.xml"); !errors.Is(err, officezip.ErrMissingPart) {
		t.Fatalf("XML(missing) err = %v, want ErrMissingPart", err)
	}
}

func TestOpenRefusesWhatIsNotAPackage(t *testing.T) {
	cases := map[string][]byte{
		"empty":       {},
		"not a zip":   []byte("this is plain text, not an office document"),
		"eocd only":   {0x50, 0x4b, 0x05, 0x06, 1, 0, 0, 0, 1, 0, 1, 0, 0xff, 0, 0, 0, 0, 0, 0, 0, 0, 0},
		"truncated":   docx(t)[:200],
		"parent path": buildZip(t, entry{"../evil.xml", "x"}),
		"absolute":    buildZip(t, entry{"/etc/passwd", "x"}),
		"backslash":   buildZip(t, entry{`word\document.xml`, "x"}),
		"drive":       buildZip(t, entry{"C:/x.xml", "x"}),
		"dot segment": buildZip(t, entry{"word/./document.xml", "x"}),
		"duplicate":   buildZip(t, entry{"word/document.xml", "a"}, entry{"Word/Document.xml", "b"}),
	}
	for name, data := range cases {
		t.Run(name, func(t *testing.T) {
			if _, err := open(t, data, officezip.Limits{}); !errors.Is(err, officezip.ErrMalformed) {
				t.Fatalf("Open err = %v, want ErrMalformed", err)
			}
		})
	}
}

func TestOpenRefusesTooManyEntries(t *testing.T) {
	data := buildZip(t, entry{"a", ""}, entry{"b", ""}, entry{"c", ""}, entry{"d", ""})
	if _, err := open(t, data, officezip.Limits{MaxEntries: 3}); !errors.Is(err, officezip.ErrTooLarge) {
		t.Fatalf("Open err = %v, want ErrTooLarge", err)
	}
	mustOpen(t, data, officezip.Limits{MaxEntries: 4})
}

func TestOpenRefusesALargeDirectory(t *testing.T) {
	data := buildZip(t, entry{strings.Repeat("n", 1000), ""}, entry{strings.Repeat("m", 1000), ""})
	if _, err := open(t, data, officezip.Limits{MaxDirectoryBytes: 1024}); !errors.Is(err, officezip.ErrTooLarge) {
		t.Fatalf("Open err = %v, want ErrTooLarge", err)
	}
}

// TestOpenChecksEntriesBeforeReadingTheDirectory declares far more entries
// than the zip holds, with a directory far larger than the file: Open must
// refuse it from the end record alone, without allocating for the directory.
func TestOpenChecksEntriesBeforeReadingTheDirectory(t *testing.T) {
	data := buildZip(t, entry{"a", "x"})
	eocd := len(data) - 22
	data[eocd+8], data[eocd+9] = 0xff, 0xfe   // entries on this disk
	data[eocd+10], data[eocd+11] = 0xff, 0xfe // entries in total
	var err error
	if got := allocated(func() { _, err = open(t, data, officezip.Limits{}) }); got > 256<<10 {
		t.Errorf("Open allocated %d bytes refusing the directory", got)
	}
	if !errors.Is(err, officezip.ErrTooLarge) {
		t.Fatalf("Open err = %v, want ErrTooLarge", err)
	}
}

// declaringZip holds one deflated entry whose directory declares it unpacks
// to declared bytes, whatever it really holds.
func declaringZip(t testing.TB, name string, declared uint64) []byte {
	t.Helper()
	var raw bytes.Buffer
	fw, err := flate.NewWriter(&raw, flate.BestCompression)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := fw.Write([]byte("<a/>")); err != nil {
		t.Fatal(err)
	}
	if err := fw.Close(); err != nil {
		t.Fatal(err)
	}
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	w, err := zw.CreateRaw(&zip.FileHeader{
		Name:               name,
		Method:             zip.Deflate,
		CompressedSize64:   uint64(raw.Len()),
		UncompressedSize64: declared,
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := w.Write(raw.Bytes()); err != nil {
		t.Fatal(err)
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

func TestPartDeclaringOneGiBFailsWithoutAllocating(t *testing.T) {
	pkg := mustOpen(t, declaringZip(t, "word/document.xml", 1<<30), officezip.Limits{})
	var partErr, xmlErr error
	got := allocated(func() {
		_, partErr = pkg.Part("word/document.xml")
		_, xmlErr = pkg.XML("word/document.xml")
	})
	if !errors.Is(partErr, officezip.ErrTooLarge) || !errors.Is(xmlErr, officezip.ErrTooLarge) {
		t.Fatalf("Part err = %v, XML err = %v, want ErrTooLarge", partErr, xmlErr)
	}
	if got > 64<<10 {
		t.Errorf("refusing a part that declares 1 GiB allocated %d bytes", got)
	}
}

func TestPartThatOutgrowsItsDeclarationFails(t *testing.T) {
	// The entry declares one byte and inflates to four; the read stops at
	// the declaration rather than trusting the stream.
	pkg := mustOpen(t, declaringZip(t, "word/document.xml", 1), officezip.Limits{})
	if _, err := readPart(pkg, "word/document.xml"); !errors.Is(err, officezip.ErrMalformed) {
		t.Fatalf("read err = %v, want ErrMalformed", err)
	}
}

func TestPartLimitedTightensOneRead(t *testing.T) {
	body := strings.Repeat("z", 300)
	data := buildZip(t, entry{"big.bin", body}, entry{"small.bin", "ok"})

	pkg := mustOpen(t, data, officezip.Limits{MaxPartBytes: 1000})
	if _, err := pkg.PartLimited("big.bin", 100); !errors.Is(err, officezip.ErrTooLarge) {
		t.Fatalf("tight read err = %v, want ErrTooLarge", err)
	}
	// A limit of zero is the package cap, so the same part is readable.
	got, err := readPartLimited(pkg, "big.bin", 0)
	if err != nil || got != body {
		t.Fatalf("zero limit read %d bytes, err %v", len(got), err)
	}

	// A limit above the package cap cannot raise it.
	pkg = mustOpen(t, data, officezip.Limits{MaxPartBytes: 100})
	if _, err := pkg.PartLimited("big.bin", 10_000); !errors.Is(err, officezip.ErrTooLarge) {
		t.Fatalf("raised limit err = %v, want ErrTooLarge", err)
	}

	size, ok := pkg.DeclaredSize("small.bin")
	if !ok || size != int64(len("ok")) {
		t.Fatalf("DeclaredSize(small.bin) = %d, %v", size, ok)
	}
	if _, ok := pkg.DeclaredSize("missing.bin"); ok {
		t.Fatal("DeclaredSize reported a part the package does not hold")
	}
}

// readPartLimited reads a whole part through PartLimited.
func readPartLimited(pkg *officezip.Package, name string, limit int64) (string, error) {
	rc, err := pkg.PartLimited(name, limit)
	if err != nil {
		return "", err
	}
	defer rc.Close()
	var sb strings.Builder
	_, err = io.Copy(&sb, rc)
	return sb.String(), err
}

func TestPartCapsAndBudget(t *testing.T) {
	big := strings.Repeat("z", 600<<10)
	data := buildZip(t, entry{"a.bin", big}, entry{"b.bin", big}, entry{"exact.bin", strings.Repeat("e", 1<<20)})

	t.Run("part past its cap is refused", func(t *testing.T) {
		pkg := mustOpen(t, data, officezip.Limits{MaxPartBytes: 512 << 10})
		if _, err := pkg.Part("a.bin"); !errors.Is(err, officezip.ErrTooLarge) {
			t.Fatalf("Part err = %v, want ErrTooLarge", err)
		}
	})

	t.Run("part filling its cap exactly is read", func(t *testing.T) {
		pkg := mustOpen(t, data, officezip.Limits{MaxPartBytes: 1 << 20})
		got, err := readPart(pkg, "exact.bin")
		if err != nil || len(got) != 1<<20 {
			t.Fatalf("read %d bytes, err %v", len(got), err)
		}
	})

	t.Run("budget refuses the part that would overspend it", func(t *testing.T) {
		pkg := mustOpen(t, data, officezip.Limits{MaxTotalBytes: 1 << 20})
		if _, err := readPart(pkg, "a.bin"); err != nil {
			t.Fatalf("first part: %v", err)
		}
		if _, err := pkg.Part("b.bin"); !errors.Is(err, officezip.ErrTooLarge) {
			t.Fatalf("second part err = %v, want ErrTooLarge", err)
		}
	})

	t.Run("budget stops a read already open", func(t *testing.T) {
		pkg := mustOpen(t, data, officezip.Limits{MaxTotalBytes: 1 << 20})
		a, err := pkg.Part("a.bin")
		if err != nil {
			t.Fatal(err)
		}
		defer a.Close()
		b, err := pkg.Part("b.bin")
		if err != nil {
			t.Fatal(err)
		}
		defer b.Close()
		if _, err := io.Copy(io.Discard, a); err != nil {
			t.Fatalf("first part: %v", err)
		}
		n, err := io.Copy(io.Discard, b)
		if !errors.Is(err, officezip.ErrTooLarge) {
			t.Fatalf("second part err = %v, want ErrTooLarge", err)
		}
		if n > (1<<20)-(600<<10) {
			t.Errorf("read %d bytes of the second part, past the budget", n)
		}
	})
}

func TestXMLStreamsTokens(t *testing.T) {
	pkg := mustOpen(t, docx(t), officezip.Limits{})
	dec, err := pkg.XML("word/document.xml")
	if err != nil {
		t.Fatal(err)
	}
	defer dec.Close()
	var texts []string
	for {
		tok, err := dec.Token()
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			t.Fatal(err)
		}
		start, ok := tok.(xml.StartElement)
		if !ok || start.Name.Local != "r" {
			continue
		}
		// A subtree decoded from the middle of the stream.
		var run struct {
			Text string `xml:"t"`
		}
		if err := dec.DecodeElement(&run, &start); err != nil {
			t.Fatal(err)
		}
		texts = append(texts, run.Text)
	}
	if strings.Join(texts, " ") != "Hello World" {
		t.Fatalf("texts = %q", texts)
	}
	if dec.Elements() != 8 {
		t.Errorf("Elements() = %d, want 8", dec.Elements())
	}
}

func TestXMLRefusesMalformedXML(t *testing.T) {
	cases := map[string]string{
		"unclosed":   "<a><b></a>",
		"bad entity": "<a>&nope;</a>",
		"garbage":    "<<<<",
	}
	for name, body := range cases {
		t.Run(name, func(t *testing.T) {
			pkg := mustOpen(t, buildZip(t, entry{"content.xml", body}), officezip.Limits{})
			dec, err := pkg.XML("content.xml")
			if err != nil {
				t.Fatal(err)
			}
			defer dec.Close()
			var v struct{}
			if err := dec.Decode(&v); !errors.Is(err, officezip.ErrMalformed) {
				t.Fatalf("Decode err = %v, want ErrMalformed", err)
			}
		})
	}
}

// drain reads every token of a part.
func drain(dec *officezip.Decoder) error {
	for {
		if _, err := dec.Token(); err != nil {
			if errors.Is(err, io.EOF) {
				return nil
			}
			return err
		}
	}
}

func TestXMLNestingBombFailsWithoutAllocating(t *testing.T) {
	const depth = 1_000_000
	bomb := strings.Repeat("<a>", depth) + strings.Repeat("</a>", depth)
	pkg := mustOpen(t, buildZip(t, entry{"content.xml", bomb}), officezip.Limits{})
	var err error
	got := allocated(func() {
		dec, openErr := pkg.XML("content.xml")
		if openErr != nil {
			err = openErr
			return
		}
		defer dec.Close()
		err = drain(dec)
	})
	if !errors.Is(err, officezip.ErrTooLarge) {
		t.Fatalf("err = %v, want ErrTooLarge", err)
	}
	if got > 1<<20 {
		t.Errorf("refusing a nesting bomb allocated %d bytes", got)
	}
}

func TestXMLElementLimit(t *testing.T) {
	body := "<r>" + strings.Repeat("<c/>", 2000) + "</r>"
	data := buildZip(t, entry{"content.xml", body})

	for name, read := range map[string]func(*officezip.Decoder) error{
		"Token":  drain,
		"Decode": func(d *officezip.Decoder) error { var v struct{}; return d.Decode(&v) },
		"Skip": func(d *officezip.Decoder) error {
			if _, err := d.Token(); err != nil {
				return err
			}
			return d.Skip()
		},
	} {
		t.Run(name, func(t *testing.T) {
			pkg := mustOpen(t, data, officezip.Limits{MaxElements: 1000})
			dec, err := pkg.XML("content.xml")
			if err != nil {
				t.Fatal(err)
			}
			defer dec.Close()
			if err := read(dec); !errors.Is(err, officezip.ErrTooLarge) {
				t.Fatalf("err = %v, want ErrTooLarge", err)
			}
			// The limit is sticky: reading on does not resume the part.
			if _, err := dec.Token(); !errors.Is(err, officezip.ErrTooLarge) {
				t.Fatalf("next Token err = %v, want ErrTooLarge", err)
			}
		})
	}

	pkg := mustOpen(t, data, officezip.Limits{MaxElements: 2001})
	dec, err := pkg.XML("content.xml")
	if err != nil {
		t.Fatal(err)
	}
	defer dec.Close()
	if err := drain(dec); err != nil {
		t.Fatalf("a part at its element limit: %v", err)
	}
}

func TestXMLPartPastItsCap(t *testing.T) {
	body := "<r>" + strings.Repeat("<c>text</c>", 10_000) + "</r>"
	pkg := mustOpen(t, buildZip(t, entry{"content.xml", body}), officezip.Limits{MaxPartBytes: 1024})
	if _, err := pkg.XML("content.xml"); !errors.Is(err, officezip.ErrTooLarge) {
		t.Fatalf("XML err = %v, want ErrTooLarge", err)
	}
}

func TestRelationships(t *testing.T) {
	pkg := mustOpen(t, docx(t), officezip.Limits{})

	root, err := pkg.Relationships("")
	if err != nil {
		t.Fatal(err)
	}
	if len(root) != 1 || root[0].Part != "word/document.xml" || root[0].External {
		t.Fatalf("package relationships = %+v", root)
	}

	rels, err := pkg.Relationships("word/document.xml")
	if err != nil {
		t.Fatal(err)
	}
	want := []officezip.Relationship{
		{ID: "rId1", Target: "media/image1.png", Part: "word/media/image1.png"},
		{ID: "rId2", Target: "https://example.com/", External: true},
		{ID: "rId3", Target: "file:///C:/evil.dotm", External: true},
		{ID: "rId4", Target: "../../../etc/passwd"},
		{ID: "rId5", Target: "/word/styles.xml", Part: "word/styles.xml"},
	}
	if len(rels) != len(want) {
		t.Fatalf("relationships = %+v", rels)
	}
	for i, w := range want {
		got := rels[i]
		got.Type = ""
		if got != w {
			t.Errorf("relationship %d = %+v, want %+v", i, got, w)
		}
	}

	none, err := pkg.Relationships("word/media/image1.png")
	if err != nil || none != nil {
		t.Fatalf("a part without relationships = %v, %v", none, err)
	}
}

func TestRelationshipsMalformed(t *testing.T) {
	pkg := mustOpen(t, buildZip(t, entry{"_rels/.rels", "<Relationships><Relationship"}), officezip.Limits{})
	if _, err := pkg.Relationships(""); !errors.Is(err, officezip.ErrMalformed) {
		t.Fatalf("err = %v, want ErrMalformed", err)
	}
}

func TestManifest(t *testing.T) {
	pkg := mustOpen(t, buildZip(t,
		entry{"mimetype", "application/vnd.oasis.opendocument.text"},
		entry{"META-INF/manifest.xml", odtManifest},
	), officezip.Limits{})
	got, err := pkg.Manifest()
	if err != nil {
		t.Fatal(err)
	}
	want := []officezip.ManifestEntry{
		{FullPath: "/", MediaType: "application/vnd.oasis.opendocument.text"},
		{FullPath: "content.xml", MediaType: "text/xml"},
		{FullPath: "Pictures/a.png", MediaType: "image/png", Encrypted: true},
	}
	if len(got) != len(want) {
		t.Fatalf("Manifest() = %+v", got)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("entry %d = %+v, want %+v", i, got[i], want[i])
		}
	}

	if _, err := mustOpen(t, docx(t), officezip.Limits{}).Manifest(); !errors.Is(err, officezip.ErrMissingPart) {
		t.Fatalf("Manifest of a package without one: err = %v, want ErrMissingPart", err)
	}
}

// FuzzOpen opens arbitrary bytes as a package and reads everything in it,
// under small limits. Nothing may panic, and every failure is one of the
// package's own errors.
func FuzzOpen(f *testing.F) {
	f.Add(docx(f))
	f.Add(buildZip(f, entry{"META-INF/manifest.xml", odtManifest}, entry{"content.xml", "<a><b/></a>"}))
	f.Add(declaringZip(f, "word/document.xml", 1<<30))
	f.Add(buildZip(f, entry{"content.xml", strings.Repeat("<a>", 300)}))
	f.Add([]byte("PK\x05\x06"))
	limits := officezip.Limits{MaxEntries: 64, MaxPartBytes: 64 << 10, MaxTotalBytes: 256 << 10, MaxElements: 4096, MaxDepth: 32}
	ours := func(t *testing.T, err error) {
		if err != nil && !errors.Is(err, officezip.ErrTooLarge) && !errors.Is(err, officezip.ErrMalformed) && !errors.Is(err, officezip.ErrMissingPart) {
			t.Fatalf("unexpected error type: %v", err)
		}
	}
	f.Fuzz(func(t *testing.T, data []byte) {
		pkg, err := officezip.Open(bytes.NewReader(data), int64(len(data)), limits)
		ours(t, err)
		if err != nil {
			return
		}
		_, err = pkg.Manifest()
		ours(t, err)
		for _, name := range pkg.Names() {
			_, err = pkg.Relationships(name)
			ours(t, err)
			dec, err := pkg.XML(name)
			ours(t, err)
			if err != nil {
				continue
			}
			ours(t, drain(dec))
			_ = dec.Close()
		}
	})
}
