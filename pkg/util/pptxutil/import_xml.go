package pptxutil

// cspell:ignore autofit clr cust descr dgm fmla gd grp lum patt ph prst scrgb srgb xfrm

import (
	"encoding/xml"
	"strconv"
	"strings"
)

// The PresentationML and DrawingML a reader needs, matched by local name: a
// part's prefixes are its own to choose, and every name read here is unique
// within the elements it can appear in. Attributes that can be malformed are
// [xInt] or plain strings, so one bad value costs the property rather than the
// slide.

// xInt is an integer attribute; one that does not parse reads as 0.
type xInt int64

func (v *xInt) UnmarshalXMLAttr(attr xml.Attr) error {
	n, _ := strconv.ParseInt(strings.TrimSpace(attr.Value), 10, 64)
	*v = xInt(n)
	return nil
}

// xBool is an xsd:boolean attribute.
type xBool bool

func (v *xBool) UnmarshalXMLAttr(attr xml.Attr) error {
	*v = xBool(attr.Value == "1" || attr.Value == "true")
	return nil
}

// xRels is a relationships part.
type xRels struct {
	Rels []xRel `xml:"Relationship"`
}

// xRel is one relationship.
type xRel struct {
	ID         string `xml:"Id,attr"`
	Type       string `xml:"Type,attr"`
	Target     string `xml:"Target,attr"`
	TargetMode string `xml:"TargetMode,attr"`
}

// xPresentation is ppt/presentation.xml.
type xPresentation struct {
	SlideSize struct {
		CX xInt `xml:"cx,attr"`
		CY xInt `xml:"cy,attr"`
	} `xml:"sldSz"`
	SlideIDs []struct {
		RelID string `xml:"http://schemas.openxmlformats.org/officeDocument/2006/relationships id,attr"`
	} `xml:"sldIdLst>sldId"`
	DefaultTextStyle *xListStyle `xml:"defaultTextStyle"`
}

// xCore is docProps/core.xml.
type xCore struct {
	Title string `xml:"title"`
}

// xTheme is a theme part: its colors and fonts.
type xTheme struct {
	Colors struct {
		Entries []xNamedColor `xml:",any"`
	} `xml:"themeElements>clrScheme"`
	MajorFont xTypeface `xml:"themeElements>fontScheme>majorFont>latin"`
	MinorFont xTypeface `xml:"themeElements>fontScheme>minorFont>latin"`
}

// xNamedColor is one color of a scheme, named by its element.
type xNamedColor struct {
	XMLName xml.Name
	xColorChoice
}

// xTypeface names a font.
type xTypeface struct {
	Typeface string `xml:"typeface,attr"`
}

// xSlidePart is a slide, layout or master: they share the parts read here.
type xSlidePart struct {
	ShowMasterShapes *string      `xml:"showMasterSp,attr"`
	Background       *xBackground `xml:"cSld>bg"`
	Tree             xGroup       `xml:"cSld>spTree"`
	ColorMap         *struct {
		Attrs []xml.Attr `xml:",any,attr"`
	} `xml:"clrMap"`
	TextStyles *struct {
		Title *xListStyle `xml:"titleStyle"`
		Body  *xListStyle `xml:"bodyStyle"`
		Other *xListStyle `xml:"otherStyle"`
	} `xml:"txStyles"`
	Timing     *struct{}    `xml:"timing"`
	Transition *xTransition `xml:"transition"`
	Alternates []xAlternate `xml:"AlternateContent"`
}

// xTransition is a slide's <p:transition>: its speed or exact duration, and
// the effect, of which only those a .qslide can play are read by name.
type xTransition struct {
	Speed string `xml:"spd,attr"`
	// Duration is p14:dur, in milliseconds.
	Duration string           `xml:"dur,attr"`
	Fade     *struct{}        `xml:"fade"`
	Push     *xTransitionSide `xml:"push"`
	Wipe     *xTransitionSide `xml:"wipe"`
	Zoom     *struct{}        `xml:"zoom"`
	// Other is every other child: an effect this cannot play, or a sound
	// (sndAc) or extension list, which are not effects.
	Other []struct {
		XMLName xml.Name
	} `xml:",any"`
}

// xTransitionSide is a push's or wipe's direction: l, r, u or d.
type xTransitionSide struct {
	Dir string `xml:"dir,attr"`
}

// xAlternate is an mc:AlternateContent at the slide's root, where PowerPoint
// puts a transition with an exact duration or a 2010 effect, with a plainer
// one as its fallback.
type xAlternate struct {
	Choices []struct {
		Transition *xTransition `xml:"transition"`
	} `xml:"Choice"`
	Fallback *struct {
		Transition *xTransition `xml:"transition"`
	} `xml:"Fallback"`
}

// xBackground is a slide's own background, or a reference into the theme's.
type xBackground struct {
	Props *struct {
		xFill
	} `xml:"bgPr"`
	Ref *struct {
		Idx xInt `xml:"idx,attr"`
		xColorChoice
	} `xml:"bgRef"`
}

// xGroup is a shape tree or group: its own transform, then its children in
// stacking order, back to front.
type xGroup struct {
	Props    xNonVisual
	Xfrm     *xXfrm
	Children []xTreeItem
}

// xTreeItem is one child of a shape tree; one of the fields is set, or Other
// names an element this reader does not draw.
type xTreeItem struct {
	Shape     *xShape
	Connector *xShape
	Picture   *xPicture
	Group     *xGroup
	Frame     *xGraphicFrame
	Other     string
}

// UnmarshalXML reads the children in document order, which is their stacking
// order. A markup-compatibility block contributes its fallback, which is what
// a reader that knows none of its choices draws.
func (g *xGroup) UnmarshalXML(d *xml.Decoder, start xml.StartElement) error {
	for {
		tok, err := d.Token()
		if err != nil {
			return err
		}
		switch tok := tok.(type) {
		case xml.EndElement:
			return nil
		case xml.StartElement:
			var item xTreeItem
			switch tok.Name.Local {
			case "nvGrpSpPr":
				err = d.DecodeElement(&g.Props, &tok)
			case "grpSpPr":
				var props struct {
					Xfrm *xXfrm `xml:"xfrm"`
				}
				err = d.DecodeElement(&props, &tok)
				g.Xfrm = props.Xfrm
			case "sp":
				item.Shape = &xShape{}
				err = d.DecodeElement(item.Shape, &tok)
			case "cxnSp":
				item.Connector = &xShape{}
				err = d.DecodeElement(item.Connector, &tok)
			case "pic":
				item.Picture = &xPicture{}
				err = d.DecodeElement(item.Picture, &tok)
			case "grpSp":
				item.Group = &xGroup{}
				err = d.DecodeElement(item.Group, &tok)
			case "graphicFrame":
				item.Frame = &xGraphicFrame{}
				err = d.DecodeElement(item.Frame, &tok)
			case "AlternateContent":
				var alt struct {
					Fallback *xGroup `xml:"Fallback"`
				}
				err = d.DecodeElement(&alt, &tok)
				if alt.Fallback != nil {
					g.Children = append(g.Children, alt.Fallback.Children...)
				}
			default:
				item.Other = tok.Name.Local
				err = d.Skip()
			}
			if err != nil {
				return err
			}
			if item != (xTreeItem{}) {
				g.Children = append(g.Children, item)
			}
		}
	}
}

// xNonVisual is the non-visual properties every drawn element opens with.
type xNonVisual struct {
	Common struct {
		Name   string `xml:"name,attr"`
		Descr  string `xml:"descr,attr"`
		Hidden xBool  `xml:"hidden,attr"`
	} `xml:"cNvPr"`
	ShapeProps struct {
		TextBox xBool `xml:"txBox,attr"`
	} `xml:"cNvSpPr"`
	App struct {
		Placeholder *xPlaceholder `xml:"ph"`
		Video       *struct{}     `xml:"videoFile"`
		Audio       *struct{}     `xml:"audioFile"`
		QuickTime   *struct{}     `xml:"quickTimeFile"`
		WavAudio    *struct{}     `xml:"wavAudioFile"`
		AudioCD     *struct{}     `xml:"audioCd"`
	} `xml:"nvPr"`
}

// xPlaceholder marks a shape that takes what it leaves unset from its layout
// and master.
type xPlaceholder struct {
	Type string `xml:"type,attr"`
	Idx  string `xml:"idx,attr"`
}

// xShape is a shape or connector.
type xShape struct {
	ShapeNV     *xNonVisual  `xml:"nvSpPr"`
	ConnectorNV *xNonVisual  `xml:"nvCxnSpPr"`
	Props       xShapeProps  `xml:"spPr"`
	Style       *xShapeStyle `xml:"style"`
	Text        *xTextBody   `xml:"txBody"`
}

// nonVisual is the shape's non-visual properties, whichever element held them.
func (s *xShape) nonVisual() xNonVisual {
	switch {
	case s.ShapeNV != nil:
		return *s.ShapeNV
	case s.ConnectorNV != nil:
		return *s.ConnectorNV
	}
	return xNonVisual{}
}

// xShapeProps is a shape's geometry, fill and outline.
type xShapeProps struct {
	Xfrm     *xXfrm `xml:"xfrm"`
	Geometry *struct {
		Preset string `xml:"prst,attr"`
		Guides []struct {
			Name    string `xml:"name,attr"`
			Formula string `xml:"fmla,attr"`
		} `xml:"avLst>gd"`
	} `xml:"prstGeom"`
	Custom *struct{} `xml:"custGeom"`
	xFill
	Line *xLine `xml:"ln"`
}

// xXfrm is a transform in EMU, rotated clockwise in 60,000ths of a degree.
type xXfrm struct {
	Rot   xInt    `xml:"rot,attr"`
	FlipH xBool   `xml:"flipH,attr"`
	FlipV xBool   `xml:"flipV,attr"`
	Off   xPoint  `xml:"off"`
	Ext   xExtent `xml:"ext"`
	// A group's child coordinate space.
	ChildOff *xPoint  `xml:"chOff"`
	ChildExt *xExtent `xml:"chExt"`
}

// xPoint is a position in EMU.
type xPoint struct {
	X xInt `xml:"x,attr"`
	Y xInt `xml:"y,attr"`
}

// xExtent is a size in EMU.
type xExtent struct {
	CX xInt `xml:"cx,attr"`
	CY xInt `xml:"cy,attr"`
}

// xFill is a fill choice; at most one is set.
type xFill struct {
	NoFill   *struct{}     `xml:"noFill"`
	Solid    *xColorChoice `xml:"solidFill"`
	Gradient *struct {
		Stops []struct {
			xColorChoice
		} `xml:"gsLst>gs"`
	} `xml:"gradFill"`
	Pattern *struct {
		Foreground *xColorChoice `xml:"fgClr"`
	} `xml:"pattFill"`
	Picture *xBlipFill `xml:"blipFill"`
	Group   *struct{}  `xml:"grpFill"`
}

// xLine is an outline.
type xLine struct {
	Width *string `xml:"w,attr"`
	xFill
	Dash *struct {
		Val string `xml:"val,attr"`
	} `xml:"prstDash"`
	Head *xLineEnd `xml:"headEnd"`
	Tail *xLineEnd `xml:"tailEnd"`
}

// xLineEnd is an arrowhead, or none.
type xLineEnd struct {
	Type string `xml:"type,attr"`
}

// xColorChoice is a color in any of the forms DrawingML writes one; at most
// one is set.
type xColorChoice struct {
	RGB    *xColor `xml:"srgbClr"`
	Scheme *xColor `xml:"schemeClr"`
	System *xColor `xml:"sysClr"`
	Preset *xColor `xml:"prstClr"`
	ScRGB  *struct {
		R xInt `xml:"r,attr"`
		G xInt `xml:"g,attr"`
		B xInt `xml:"b,attr"`
		xColorTransforms
	} `xml:"scrgbClr"`
}

// xColor is a color value and the transforms applied to it.
type xColor struct {
	Val     string `xml:"val,attr"`
	LastClr string `xml:"lastClr,attr"`
	xColorTransforms
}

// xColorTransforms are the color transforms this reader applies; values are
// in 1,000ths of a percent.
type xColorTransforms struct {
	Alpha  *xValue `xml:"alpha"`
	LumMod *xValue `xml:"lumMod"`
	LumOff *xValue `xml:"lumOff"`
	Shade  *xValue `xml:"shade"`
	Tint   *xValue `xml:"tint"`
}

// xValue is an element whose val attribute is all it carries.
type xValue struct {
	Val xInt `xml:"val,attr"`
}

// xShapeStyle is a shape's references into the theme's styles.
type xShapeStyle struct {
	Line xStyleRef `xml:"lnRef"`
	Fill xStyleRef `xml:"fillRef"`
	Font xStyleRef `xml:"fontRef"`
}

// xStyleRef is one style reference: an index, 0 for none, and the color it
// is drawn in.
type xStyleRef struct {
	Idx string `xml:"idx,attr"`
	xColorChoice
}

// xPicture is a picture.
type xPicture struct {
	NV    xNonVisual  `xml:"nvPicPr"`
	Fill  xBlipFill   `xml:"blipFill"`
	Props xShapeProps `xml:"spPr"`
}

// xBlipFill is a picture fill: the picture's relationship and its crop.
type xBlipFill struct {
	Blip *struct {
		Embed string `xml:"embed,attr"`
		Link  string `xml:"link,attr"`
	} `xml:"blip"`
	Crop *struct {
		L xInt `xml:"l,attr"`
		T xInt `xml:"t,attr"`
		R xInt `xml:"r,attr"`
		B xInt `xml:"b,attr"`
	} `xml:"srcRect"`
}

// xGraphicFrame holds a table, chart, diagram or embedded object.
type xGraphicFrame struct {
	Props xNonVisual `xml:"nvGraphicFramePr"`
	Xfrm  *xXfrm     `xml:"xfrm"`
	Data  struct {
		URI   string  `xml:"uri,attr"`
		Table *xTable `xml:"tbl"`
	} `xml:"graphic>graphicData"`
}

// xTable is a table: whether its first row is a header and its rows banded,
// its column widths, and its rows.
type xTable struct {
	Props struct {
		FirstRow xBool `xml:"firstRow,attr"`
		BandRow  xBool `xml:"bandRow,attr"`
	} `xml:"tblPr"`
	Grid []struct {
		W xInt `xml:"w,attr"`
	} `xml:"tblGrid>gridCol"`
	Rows []xTableRow `xml:"tr"`
}

// xTableRow is one row of a table: its height and its cells.
type xTableRow struct {
	H     xInt         `xml:"h,attr"`
	Cells []xTableCell `xml:"tc"`
}

// xTableCell is one cell: its merge, its text, and its properties.
type xTableCell struct {
	GridSpan xInt       `xml:"gridSpan,attr"`
	RowSpan  xInt       `xml:"rowSpan,attr"`
	HMerge   xBool      `xml:"hMerge,attr"`
	VMerge   xBool      `xml:"vMerge,attr"`
	Text     *xTextBody `xml:"txBody"`
	Props    *struct {
		Anchor string `xml:"anchor,attr"`
		Left   *xLine `xml:"lnL"`
		Right  *xLine `xml:"lnR"`
		Top    *xLine `xml:"lnT"`
		Bottom *xLine `xml:"lnB"`
		xFill
	} `xml:"tcPr"`
}

// xTextBody is a shape's text.
type xTextBody struct {
	Body       *xBodyProps  `xml:"bodyPr"`
	ListStyle  *xListStyle  `xml:"lstStyle"`
	Paragraphs []xParagraph `xml:"p"`
}

// xBodyProps is a text body's insets, anchoring and auto-fit.
type xBodyProps struct {
	LeftInset    *string   `xml:"lIns,attr"`
	TopInset     *string   `xml:"tIns,attr"`
	RightInset   *string   `xml:"rIns,attr"`
	BottomInset  *string   `xml:"bIns,attr"`
	Anchor       string    `xml:"anchor,attr"`
	NoAutofit    *struct{} `xml:"noAutofit"`
	NormAutofit  *struct{} `xml:"normAutofit"`
	ShapeAutofit *struct{} `xml:"spAutoFit"`
}

// xListStyle is the paragraph style of each of the nine outline levels.
type xListStyle struct {
	Levels [9]*xParaProps
}

func (s *xListStyle) UnmarshalXML(d *xml.Decoder, start xml.StartElement) error {
	for {
		tok, err := d.Token()
		if err != nil {
			return err
		}
		switch tok := tok.(type) {
		case xml.EndElement:
			return nil
		case xml.StartElement:
			// lvl1pPr through lvl9pPr.
			name := tok.Name.Local
			if len(name) == 7 && strings.HasPrefix(name, "lvl") && strings.HasSuffix(name, "pPr") &&
				name[3] >= '1' && name[3] <= '9' {
				props := &xParaProps{}
				if err := d.DecodeElement(props, &tok); err != nil {
					return err
				}
				s.Levels[name[3]-'1'] = props
				continue
			}
			if err := d.Skip(); err != nil {
				return err
			}
		}
	}
}

// xParaProps is a paragraph's properties, or an outline level's defaults.
type xParaProps struct {
	Level       xInt   `xml:"lvl,attr"`
	Align       string `xml:"algn,attr"`
	LineSpacing *struct {
		Percent *xValue `xml:"spcPct"`
		Points  *xValue `xml:"spcPts"`
	} `xml:"lnSpc"`
	NoBullet   *struct{}  `xml:"buNone"`
	CharBullet *struct{}  `xml:"buChar"`
	AutoNumber *struct{}  `xml:"buAutoNum"`
	PicBullet  *struct{}  `xml:"buBlip"`
	Defaults   *xRunProps `xml:"defRPr"`
}

// xParagraph is one paragraph: its properties and its runs in order. A line
// break is a run with Break set.
type xParagraph struct {
	Props *xParaProps
	Runs  []xRun
	End   *xRunProps
}

// xRun is a span of text, a field's current text, or a line break.
type xRun struct {
	Props *xRunProps `xml:"rPr"`
	Text  string     `xml:"t"`
	Break bool       `xml:"-"`
}

func (p *xParagraph) UnmarshalXML(d *xml.Decoder, start xml.StartElement) error {
	for {
		tok, err := d.Token()
		if err != nil {
			return err
		}
		switch tok := tok.(type) {
		case xml.EndElement:
			return nil
		case xml.StartElement:
			switch tok.Name.Local {
			case "pPr":
				p.Props = &xParaProps{}
				err = d.DecodeElement(p.Props, &tok)
			case "r", "fld":
				var run xRun
				err = d.DecodeElement(&run, &tok)
				p.Runs = append(p.Runs, run)
			case "br":
				run := xRun{Break: true}
				err = d.DecodeElement(&run, &tok)
				run.Text = ""
				p.Runs = append(p.Runs, run)
			case "endParaRPr":
				p.End = &xRunProps{}
				err = d.DecodeElement(p.End, &tok)
			default:
				err = d.Skip()
			}
			if err != nil {
				return err
			}
		}
	}
}

// xRunProps is a run's character style; an attribute left out inherits.
type xRunProps struct {
	Size      *string `xml:"sz,attr"`
	Bold      *string `xml:"b,attr"`
	Italic    *string `xml:"i,attr"`
	Underline *string `xml:"u,attr"`
	Strike    *string `xml:"strike,attr"`
	xFill
	Latin *xTypeface `xml:"latin"`
}
