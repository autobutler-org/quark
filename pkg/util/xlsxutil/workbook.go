package xlsxutil

import (
	"encoding/xml"
	"fmt"
	"io"
	"time"

	"github.com/autobutler-org/quark/pkg/util/officezip"
)

// officeDocumentRel is the relationship type naming the package's main part,
// which for a spreadsheet is the workbook.
const officeDocumentRel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"

// worksheetRel is the relationship type naming one worksheet of a workbook.
const worksheetRel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet"

// relationshipNS is the namespace a <sheet>'s r:id attribute is qualified by.
// Matched on the attribute's namespace rather than its "r:" prefix, which a
// writer is free to name something else.
const relationshipNS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"

// defaultWorkbookPart is where every writer in practice puts the workbook. It
// is the fallback for a package whose root relationships do not name one.
const defaultWorkbookPart = "xl/workbook.xml"

// excelEpoch is the day serial 0 denotes under the 1900 date system. It is
// 1899-12-30 rather than 1899-12-31 because Excel counts a 29th of February
// 1900 that never happened, and every serial after it inherits the extra day.
var excelEpoch = time.Date(1899, time.December, 30, 0, 0, 0, 0, time.UTC)

// excelEpoch1904 is the same for a workbook saved with the 1904 date system,
// which has no phantom leap day to correct for.
var excelEpoch1904 = time.Date(1904, time.January, 1, 0, 0, 0, 0, time.UTC)

// readWorkbook resolves the package: it finds the workbook and pairs each
// worksheet's tab name with the part holding its rows. Relationship targets
// are resolved by officezip, which refuses one that climbs out of the package.
func readWorkbook(pkg *officezip.Package) (workbook, error) {
	workbookPart := findWorkbookPart(pkg)
	if workbookPart == "" {
		return workbook{}, fmt.Errorf("%w: no workbook part", ErrNotSpreadsheet)
	}

	names, date1904, err := readSheetNames(pkg, workbookPart)
	if err != nil {
		return workbook{}, err
	}
	if len(names) == 0 {
		return workbook{}, fmt.Errorf("%w: workbook declares no sheets", ErrNotSpreadsheet)
	}
	if len(names) > MaxSheets {
		return workbook{}, fmt.Errorf("%w: %d sheets exceeds the maximum of %d", ErrTooLarge, len(names), MaxSheets)
	}

	targets, err := partRels(pkg, workbookPart)
	if err != nil {
		return workbook{}, err
	}

	epoch := excelEpoch
	if date1904 {
		epoch = excelEpoch1904
	}

	book := workbook{pkg: pkg, epoch: epoch}
	for _, s := range names {
		rel, ok := targets[s.relID]
		if !ok || rel.Type != worksheetRel || rel.Part == "" || !pkg.Has(rel.Part) {
			// A <sheet> whose relationship is absent, climbs out of the
			// package, or points at something that is not a worksheet — a
			// chartsheet, say — has no rows to convert. Skipping it keeps the
			// rest of the workbook readable.
			continue
		}
		book.sheets = append(book.sheets, sheetRef{name: s.name, part: rel.Part})
	}
	if len(book.sheets) == 0 {
		return workbook{}, fmt.Errorf("%w: workbook has no readable worksheets", ErrNotSpreadsheet)
	}
	return book, nil
}

// findWorkbookPart reads the package's root relationships for the part marked
// as the office document. A package that does not name one, or whose root
// relationships cannot be read, falls back to where every writer puts it.
func findWorkbookPart(pkg *officezip.Package) string {
	rels, err := pkg.Relationships("")
	if err == nil {
		for _, rel := range rels {
			if rel.Type == officeDocumentRel && rel.Part != "" && pkg.Has(rel.Part) {
				return rel.Part
			}
		}
	}
	if pkg.Has(defaultWorkbookPart) {
		return defaultWorkbookPart
	}
	return ""
}

// partRels reads a part's relationships by id. A package with no such part
// has none, which is not an error here — the caller decides whether what it
// was looking for was required. A repeated id keeps the last one.
func partRels(pkg *officezip.Package, part string) (map[string]officezip.Relationship, error) {
	rels, err := pkg.Relationships(part)
	if err != nil {
		return nil, wrapPackage(err)
	}
	byID := make(map[string]officezip.Relationship, len(rels))
	for _, rel := range rels {
		if rel.ID != "" {
			byID[rel.ID] = rel
		}
	}
	return byID, nil
}

// sheetName pairs a tab's name with the relationship naming the part that
// holds its rows.
type sheetName struct {
	name  string
	relID string
}

// readSheetNames streams the workbook part for its <sheet> entries, in the
// order they are declared, and for whether the workbook counts dates from
// 1904. The attributes are read off the element rather than decoded into a
// struct because r:id is namespace-qualified, and matching it by namespace is
// what keeps a writer's choice of prefix from mattering.
func readSheetNames(pkg *officezip.Package, name string) ([]sheetName, bool, error) {
	rc, err := openPart(pkg, name, MaxPartBytes)
	if err != nil {
		return nil, false, err
	}
	defer rc.Close()

	var (
		sheets   []sheetName
		date1904 bool
	)
	dec := xml.NewDecoder(rc)
	for {
		tok, err := dec.Token()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, false, partError(name, err)
		}
		start, ok := tok.(xml.StartElement)
		if !ok {
			continue
		}
		switch start.Name.Local {
		case "workbookPr":
			for _, attr := range start.Attr {
				if attr.Name.Local == "date1904" && (attr.Value == "1" || attr.Value == "true") {
					date1904 = true
				}
			}
		case "sheet":
			var s sheetName
			for _, attr := range start.Attr {
				switch {
				case attr.Name.Local == "name" && attr.Name.Space == "":
					s.name = attr.Value
				case attr.Name.Local == "id" && attr.Name.Space == relationshipNS:
					s.relID = attr.Value
				}
			}
			if s.relID != "" {
				sheets = append(sheets, s)
			}
		}
	}
	return sheets, date1904, nil
}
