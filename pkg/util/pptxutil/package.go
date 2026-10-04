package pptxutil

// cspell:ignore cmpd dcterms hlink horz prst srgb xfrm

import (
	"encoding/xml"
	"fmt"
	"io"
	"slices"
	"strings"
)

// The namespaces and headers the parts declare.
const (
	nsMain          = "http://schemas.openxmlformats.org/presentationml/2006/main"
	nsDrawing       = "http://schemas.openxmlformats.org/drawingml/2006/main"
	nsRelationships = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
	nsPackageRels   = "http://schemas.openxmlformats.org/package/2006/relationships"
	xmlHeader       = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>` + "\n"
	// pmlNamespaces declares the three namespaces a PresentationML root uses.
	pmlNamespaces = ` xmlns:a="` + nsDrawing + `" xmlns:r="` + nsRelationships + `" xmlns:p="` + nsMain + `"`
	// ctPML prefixes the PresentationML content types.
	ctPML = "application/vnd.openxmlformats-officedocument.presentationml"
	// themeFont is the theme's font, the closest common one to the sans-serif
	// the editor draws unstyled text in.
	themeFont = "Arial"
	// emptyGroup is the shape tree's own properties, which every slide,
	// layout and master begins its tree with.
	emptyGroup = `<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>` +
		`<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/>` +
		`<a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>`
	// colorMap maps the theme's colors onto the roles text and backgrounds
	// take them in: dark text on a light background.
	colorMap = `bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" ` +
		`accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"`
	// textStyle is the first-level paragraph style every text default is: the
	// theme font in its text color.
	textStyle = `<a:lvl1pPr><a:defRPr sz="%d"><a:solidFill><a:schemeClr val="tx1"/></a:solidFill>` +
		`<a:latin typeface="+mn-lt"/></a:defRPr></a:lvl1pPr>`
	// notesWidth and notesHeight are a portrait notes page, 7.5 in by 10 in.
	notesWidth  = 6_858_000
	notesHeight = 9_144_000
)

// writePackageParts writes everything but the slides: the presentation and
// its relationships, master, layout, themes, notes master, properties and
// content types.
func (e *exporter) writePackageParts(title string) error {
	slides := len(e.notes)
	notesCount := 0
	for _, has := range e.notes {
		if has {
			notesCount++
		}
	}
	parts := []struct {
		name string
		body string
	}{
		{"ppt/presentation.xml", e.presentationPart()},
		{"ppt/_rels/presentation.xml.rels", presentationRelsPart(slides)},
		{"ppt/slideMasters/slideMaster1.xml", slideMasterPart},
		{"ppt/slideMasters/_rels/slideMaster1.xml.rels", xmlHeader + `<Relationships xmlns="` + nsPackageRels + `">` +
			relationship(1, "slideLayout", "../slideLayouts/slideLayout1.xml") +
			relationship(2, "theme", "../theme/theme1.xml") + `</Relationships>`},
		{"ppt/slideLayouts/slideLayout1.xml", slideLayoutPart},
		{"ppt/slideLayouts/_rels/slideLayout1.xml.rels", xmlHeader + `<Relationships xmlns="` + nsPackageRels + `">` +
			relationship(1, "slideMaster", "../slideMasters/slideMaster1.xml") + `</Relationships>`},
		{"ppt/theme/theme1.xml", themePart("Quark")},
		{"ppt/notesMasters/notesMaster1.xml", e.notesMasterPart()},
		{"ppt/notesMasters/_rels/notesMaster1.xml.rels", xmlHeader + `<Relationships xmlns="` + nsPackageRels + `">` +
			relationship(1, "theme", "../theme/theme2.xml") + `</Relationships>`},
		{"ppt/theme/theme2.xml", themePart("Quark Notes")},
		{"ppt/presProps.xml", xmlHeader + `<p:presentationPr` + pmlNamespaces + `/>`},
		{"ppt/viewProps.xml", xmlHeader + `<p:viewPr` + pmlNamespaces + `/>`},
		{"ppt/tableStyles.xml", xmlHeader + `<a:tblStyleLst xmlns:a="` + nsDrawing +
			`" def="{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}"/>`},
		{"docProps/core.xml", corePart(title)},
		{"docProps/app.xml", fmt.Sprintf(xmlHeader+
			`<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">`+
			`<Application>Quark</Application><Slides>%d</Slides><Notes>%d</Notes></Properties>`, slides, notesCount)},
		{"_rels/.rels", xmlHeader + `<Relationships xmlns="` + nsPackageRels + `">` +
			relationship(1, "officeDocument", "ppt/presentation.xml") +
			`<Relationship Id="rId2" Type="` + nsPackageRels + `/metadata/core-properties" Target="docProps/core.xml"/>` +
			relationship(3, "extended-properties", "docProps/app.xml") + `</Relationships>`},
		{"[Content_Types].xml", e.contentTypesPart()},
	}
	for _, part := range parts {
		if err := writePart(e.zw, part.name, part.body); err != nil {
			return err
		}
	}
	return nil
}

// presentationPart lists the master, notes master and slides, and sets the
// slide size. Relationship ids follow presentationRelsPart.
func (e *exporter) presentationPart() string {
	var b strings.Builder
	b.WriteString(xmlHeader + `<p:presentation` + pmlNamespaces + ` saveSubsetFonts="1">`)
	b.WriteString(`<p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>`)
	b.WriteString(`<p:notesMasterIdLst><p:notesMasterId r:id="rId2"/></p:notesMasterIdLst>`)
	if len(e.notes) > 0 {
		b.WriteString(`<p:sldIdLst>`)
		for i := range e.notes {
			// Slide ids start at 256; relationships 1–6 are taken.
			fmt.Fprintf(&b, `<p:sldId id="%d" r:id="rId%d"/>`, 256+i, 7+i)
		}
		b.WriteString(`</p:sldIdLst>`)
	}
	fmt.Fprintf(&b, `<p:sldSz cx="%d" cy="%d"/><p:notesSz cx="%d" cy="%d"/>`, e.cx, e.cy, notesWidth, notesHeight)
	b.WriteString(`<p:defaultTextStyle>` + fmt.Sprintf(textStyle, 1800) + `</p:defaultTextStyle>`)
	b.WriteString(`</p:presentation>`)
	return b.String()
}

// presentationRelsPart points rId1–6 at the master, notes master, theme and
// properties, and rId7 on at the slides.
func presentationRelsPart(slides int) string {
	var b strings.Builder
	b.WriteString(xmlHeader + `<Relationships xmlns="` + nsPackageRels + `">`)
	b.WriteString(relationship(1, "slideMaster", "slideMasters/slideMaster1.xml"))
	b.WriteString(relationship(2, "notesMaster", "notesMasters/notesMaster1.xml"))
	b.WriteString(relationship(3, "theme", "theme/theme1.xml"))
	b.WriteString(relationship(4, "presProps", "presProps.xml"))
	b.WriteString(relationship(5, "viewProps", "viewProps.xml"))
	b.WriteString(relationship(6, "tableStyles", "tableStyles.xml"))
	for i := range slides {
		b.WriteString(relationship(7+i, "slide", fmt.Sprintf("slides/slide%d.xml", i+1)))
	}
	b.WriteString(`</Relationships>`)
	return b.String()
}

// slideMasterPart is the one master: a background in the theme's light color
// and no placeholders, since every exported shape carries its own position.
var slideMasterPart = xmlHeader + `<p:sldMaster` + pmlNamespaces + `>` +
	`<p:cSld><p:bg><p:bgRef idx="1001"><a:schemeClr val="bg1"/></p:bgRef></p:bg>` +
	`<p:spTree>` + emptyGroup + `</p:spTree></p:cSld>` +
	`<p:clrMap ` + colorMap + `/>` +
	`<p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst>` +
	`<p:txStyles>` +
	`<p:titleStyle>` + fmt.Sprintf(textStyle, 4400) + `</p:titleStyle>` +
	`<p:bodyStyle>` + fmt.Sprintf(textStyle, 1800) + `</p:bodyStyle>` +
	`<p:otherStyle>` + fmt.Sprintf(textStyle, 1800) + `</p:otherStyle>` +
	`</p:txStyles></p:sldMaster>`

// slideLayoutPart is the one layout every slide uses: blank.
var slideLayoutPart = xmlHeader + `<p:sldLayout` + pmlNamespaces + ` type="blank" preserve="1">` +
	`<p:cSld name="Blank"><p:spTree>` + emptyGroup + `</p:spTree></p:cSld>` +
	`<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>`

// notesMasterPart lays out a notes page: the slide's picture above its notes.
func (e *exporter) notesMasterPart() string {
	// The slide picture fits a 6.67 in by 4.17 in box at the top of the page.
	const boxW, boxH = 6_096_000, 3_810_000
	w, h := int64(boxW), int64(float64(boxW)*float64(e.cy)/float64(e.cx))
	if h > boxH {
		w, h = int64(float64(boxH)*float64(e.cx)/float64(e.cy)), boxH
	}
	return xmlHeader + `<p:notesMaster` + pmlNamespaces + `>` +
		`<p:cSld><p:bg><p:bgRef idx="1001"><a:schemeClr val="bg1"/></p:bgRef></p:bg><p:spTree>` + emptyGroup +
		`<p:sp><p:nvSpPr><p:cNvPr id="2" name="Slide Image Placeholder 1"/>` +
		`<p:cNvSpPr><a:spLocks noGrp="1" noRot="1" noChangeAspect="1"/></p:cNvSpPr>` +
		`<p:nvPr><p:ph type="sldImg" idx="2"/></p:nvPr></p:nvSpPr>` +
		fmt.Sprintf(`<p:spPr><a:xfrm><a:off x="%d" y="685800"/><a:ext cx="%d" cy="%d"/></a:xfrm>`, (notesWidth-w)/2, w, h) +
		`<a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/>` +
		`<a:ln w="12700"><a:solidFill><a:prstClr val="black"/></a:solidFill></a:ln></p:spPr></p:sp>` +
		`<p:sp><p:nvSpPr><p:cNvPr id="3" name="Notes Placeholder 2"/>` +
		`<p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr><p:ph type="body" sz="quarter" idx="3"/></p:nvPr></p:nvSpPr>` +
		`<p:spPr><a:xfrm><a:off x="685800" y="4800600"/><a:ext cx="5486400" cy="3657600"/></a:xfrm>` +
		`<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr>` +
		`<p:txBody><a:bodyPr vert="horz" lIns="91440" tIns="45720" rIns="91440" bIns="45720" rtlCol="0"/>` +
		`<a:lstStyle/><a:p><a:endParaRPr lang="en-US"/></a:p></p:txBody></p:sp>` +
		`</p:spTree></p:cSld><p:clrMap ` + colorMap + `/>` +
		`<p:notesStyle>` + fmt.Sprintf(textStyle, 1200) + `</p:notesStyle></p:notesMaster>`
}

// notesSlidePart is one slide's speaker notes, a paragraph per line.
func notesSlidePart(notes string) string {
	var b strings.Builder
	b.WriteString(xmlHeader + `<p:notes` + pmlNamespaces + `><p:cSld><p:spTree>` + emptyGroup)
	b.WriteString(`<p:sp><p:nvSpPr><p:cNvPr id="2" name="Slide Image Placeholder 1"/>` +
		`<p:cNvSpPr><a:spLocks noGrp="1" noRot="1" noChangeAspect="1"/></p:cNvSpPr>` +
		`<p:nvPr><p:ph type="sldImg"/></p:nvPr></p:nvSpPr><p:spPr/></p:sp>`)
	b.WriteString(`<p:sp><p:nvSpPr><p:cNvPr id="3" name="Notes Placeholder 2"/>` +
		`<p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr><p:ph type="body" idx="1"/></p:nvPr></p:nvSpPr>` +
		`<p:spPr/><p:txBody><a:bodyPr/><a:lstStyle/>`)
	for _, line := range strings.Split(strings.ReplaceAll(notes, "\r\n", "\n"), "\n") {
		if line == "" {
			b.WriteString(`<a:p><a:endParaRPr lang="en-US"/></a:p>`)
			continue
		}
		b.WriteString(`<a:p><a:r><a:rPr lang="en-US" dirty="0"/><a:t>`)
		escape(&b, line)
		b.WriteString(`</a:t></a:r></a:p>`)
	}
	b.WriteString(`</p:txBody></p:sp></p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:notes>`)
	return b.String()
}

// themePart is a plain theme: black on white, the theme font for headings and
// body, and flat fill, line and effect styles.
func themePart(name string) string {
	solid := `<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>`
	line := `<a:ln w="%d" cap="flat" cmpd="sng" algn="ctr">` + solid + `<a:prstDash val="solid"/><a:miter lim="800000"/></a:ln>`
	fonts := `<a:latin typeface="` + themeFont + `"/><a:ea typeface=""/><a:cs typeface=""/>`
	return xmlHeader + `<a:theme xmlns:a="` + nsDrawing + `" name="` + name + `"><a:themeElements>` +
		`<a:clrScheme name="Quark">` +
		`<a:dk1><a:srgbClr val="000000"/></a:dk1><a:lt1><a:srgbClr val="FFFFFF"/></a:lt1>` +
		`<a:dk2><a:srgbClr val="1F2937"/></a:dk2><a:lt2><a:srgbClr val="F3F4F6"/></a:lt2>` +
		`<a:accent1><a:srgbClr val="3366FF"/></a:accent1><a:accent2><a:srgbClr val="E8590C"/></a:accent2>` +
		`<a:accent3><a:srgbClr val="2F9E44"/></a:accent3><a:accent4><a:srgbClr val="F59F00"/></a:accent4>` +
		`<a:accent5><a:srgbClr val="7048E8"/></a:accent5><a:accent6><a:srgbClr val="C2255C"/></a:accent6>` +
		`<a:hlink><a:srgbClr val="1C7ED6"/></a:hlink><a:folHlink><a:srgbClr val="862E9C"/></a:folHlink>` +
		`</a:clrScheme>` +
		`<a:fontScheme name="Quark"><a:majorFont>` + fonts + `</a:majorFont><a:minorFont>` + fonts + `</a:minorFont></a:fontScheme>` +
		`<a:fmtScheme name="Quark">` +
		`<a:fillStyleLst>` + strings.Repeat(solid, 3) + `</a:fillStyleLst>` +
		`<a:lnStyleLst>` + fmt.Sprintf(line, 6350) + fmt.Sprintf(line, 12700) + fmt.Sprintf(line, 19050) + `</a:lnStyleLst>` +
		`<a:effectStyleLst>` + strings.Repeat(`<a:effectStyle><a:effectLst/></a:effectStyle>`, 3) + `</a:effectStyleLst>` +
		`<a:bgFillStyleLst>` + strings.Repeat(solid, 3) + `</a:bgFillStyleLst>` +
		`</a:fmtScheme></a:themeElements><a:objectDefaults/><a:extraClrSchemeLst/></a:theme>`
}

// corePart carries the presentation's title.
func corePart(title string) string {
	var b strings.Builder
	b.WriteString(xmlHeader + `<cp:coreProperties ` +
		`xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" ` +
		`xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" ` +
		`xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><dc:title>`)
	escape(&b, title)
	b.WriteString(`</dc:title></cp:coreProperties>`)
	return b.String()
}

// contentTypesPart declares the type of every part in the package.
func (e *exporter) contentTypesPart() string {
	var b strings.Builder
	b.WriteString(xmlHeader + `<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">`)
	b.WriteString(`<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>`)
	b.WriteString(`<Default Extension="xml" ContentType="application/xml"/>`)
	exts := make([]string, 0, len(e.imageExts))
	for ext := range e.imageExts {
		exts = append(exts, ext)
	}
	slices.Sort(exts)
	for _, ext := range exts {
		fmt.Fprintf(&b, `<Default Extension="%s" ContentType="image/%s"/>`, ext, ext)
	}
	override := func(part, contentType string) {
		fmt.Fprintf(&b, `<Override PartName="/%s" ContentType="%s"/>`, part, contentType)
	}
	override("ppt/presentation.xml", ctPML+".presentation.main+xml")
	override("ppt/slideMasters/slideMaster1.xml", ctPML+".slideMaster+xml")
	override("ppt/slideLayouts/slideLayout1.xml", ctPML+".slideLayout+xml")
	override("ppt/notesMasters/notesMaster1.xml", ctPML+".notesMaster+xml")
	override("ppt/theme/theme1.xml", "application/vnd.openxmlformats-officedocument.theme+xml")
	override("ppt/theme/theme2.xml", "application/vnd.openxmlformats-officedocument.theme+xml")
	override("ppt/presProps.xml", ctPML+".presProps+xml")
	override("ppt/viewProps.xml", ctPML+".viewProps+xml")
	override("ppt/tableStyles.xml", ctPML+".tableStyles+xml")
	override("docProps/core.xml", "application/vnd.openxmlformats-package.core-properties+xml")
	override("docProps/app.xml", "application/vnd.openxmlformats-officedocument.extended-properties+xml")
	for i, has := range e.notes {
		override(fmt.Sprintf("ppt/slides/slide%d.xml", i+1), ctPML+".slide+xml")
		if has {
			override(fmt.Sprintf("ppt/notesSlides/notesSlide%d.xml", i+1), ctPML+".notesSlide+xml")
		}
	}
	b.WriteString(`</Types>`)
	return b.String()
}

// escape writes s as XML character data. EscapeText also escapes quotes, so
// the same call serves attribute values, and replaces the control characters
// XML cannot carry.
func escape(out io.Writer, s string) {
	// The writers here are a partWriter or a strings.Builder: the first keeps
	// its error for the caller's Flush, and the second cannot fail.
	_ = xml.EscapeText(out, []byte(s))
}
