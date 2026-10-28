package xlsxutil

import (
	"encoding/xml"
	"fmt"
	"io"
	"strings"

	"github.com/autobutler-org/quark/pkg/util/officezip"
)

// sharedStringsPart is where a workbook keeps its string table. Its location
// is a relationship like any other, but every writer puts it here, and reading
// it is optional — a workbook whose cells are all numeric has none.
const sharedStringsPart = "xl/sharedStrings.xml"

// readSharedStrings loads the workbook's string table. A cell of type "s"
// carries an index into this slice rather than its own text, so unlike the
// rows this cannot be streamed past — it is held whole and bounded by
// [MaxSharedStringBytes] instead.
func readSharedStrings(pkg *officezip.Package) ([]string, error) {
	if !pkg.Has(sharedStringsPart) {
		return nil, nil
	}
	rc, err := openPart(pkg, sharedStringsPart, MaxSharedStringBytes)
	if err != nil {
		return nil, err
	}
	defer rc.Close()

	var (
		strs  []string
		total int
	)
	dec := xml.NewDecoder(rc)
	for {
		tok, err := dec.Token()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, partError(sharedStringsPart, err)
		}
		start, ok := tok.(xml.StartElement)
		if !ok || start.Name.Local != "si" {
			continue
		}
		if len(strs) >= MaxSharedStrings {
			return nil, fmt.Errorf("%w: more than %d shared strings", ErrTooLarge, MaxSharedStrings)
		}
		var item sharedItem
		if err := dec.DecodeElement(&item, &start); err != nil {
			return nil, partError(sharedStringsPart, err)
		}
		s := item.text()
		total += len(s)
		if total > MaxSharedStringBytes {
			return nil, fmt.Errorf("%w: shared strings exceed %d bytes", ErrTooLarge, MaxSharedStringBytes)
		}
		strs = append(strs, s)
	}
	return strs, nil
}

// text is the string a shared item denotes: its own text, or the formatting
// runs of a rich-text item joined back together.
func (s sharedItem) text() string {
	if len(s.R) > 0 {
		var b strings.Builder
		for _, run := range s.R {
			b.WriteString(run.T)
		}
		return b.String()
	}
	if s.T != nil {
		return *s.T
	}
	return ""
}
