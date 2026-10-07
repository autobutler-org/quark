package pptxutil

// cspell:ignore autofit ph

import (
	"math"
	"strconv"
	"strings"
)

// textBox converts a shape's text body to a text box over frame, inset as
// PowerPoint insets it: the editor draws text flush with its frame. What the
// shape leaves unset comes from chain, the placeholders it inherits from.
func (s *slideReader) textBox(sp *xShape, chain []*xShape, ph *xPlaceholder, frame outFrame, t transform) outText {
	bodies := []*xBodyProps{sp.Text.Body}
	lists := []*xListStyle{sp.Text.ListStyle}
	for _, inherited := range chain {
		if inherited.Text != nil {
			bodies = append(bodies, inherited.Text.Body)
			lists = append(lists, inherited.Text.ListStyle)
		}
	}
	lists = append(lists, s.textStyle(ph))

	box := outText{ID: s.id(), Type: typeText, Frame: s.inset(frame, bodies, t), Paragraphs: []outParagraph{}}
	for _, body := range bodies {
		if body != nil && box.Anchor == "" {
			box.Anchor = map[string]string{"ctr": "middle", "b": "bottom"}[body.Anchor]
		}
	}
	box.AutoFit = "fixed"
	for _, body := range bodies {
		if body == nil {
			continue
		}
		if body.NoAutofit != nil || body.NormAutofit != nil || body.ShapeAutofit != nil {
			switch {
			case body.NormAutofit != nil:
				box.AutoFit = "shrink"
			case body.ShapeAutofit != nil:
				box.AutoFit = ""
			}
			break
		}
	}

	var fontColor string
	if ref := styleRef(sp.Style, "font"); ref != nil && ref.Idx != "" {
		fontColor = s.hex(&ref.xColorChoice)
	}
	for _, p := range sp.Text.Paragraphs {
		box.Paragraphs = append(box.Paragraphs, s.paragraphs(p, lists, fontColor)...)
	}
	return box
}

// inset shrinks a text box's frame by its body's insets.
func (s *slideReader) inset(frame outFrame, bodies []*xBodyProps, t transform) outFrame {
	var insets [4]float64
	for i, def := range defaultInsets {
		value := def
		for _, body := range bodies {
			if body == nil {
				continue
			}
			attr := [4]*string{body.LeftInset, body.TopInset, body.RightInset, body.BottomInset}[i]
			if attr != nil {
				if n, err := strconv.ParseInt(strings.TrimSpace(*attr), 10, 64); err == nil && n >= 0 {
					value = n
					break
				}
			}
		}
		scale := t.sx
		if i%2 == 1 {
			scale = t.sy
		}
		insets[i] = float64(value) * scale / s.scale
	}
	// The frame shrinks about its center, so a rotated box stays put.
	w := math.Max(frame.Width-insets[0]-insets[2], 0)
	h := math.Max(frame.Height-insets[1]-insets[3], 0)
	frame.X = round(frame.X + insets[0])
	frame.Y = round(frame.Y + insets[1])
	frame.Width, frame.Height = round(w), round(h)
	return frame
}

// textStyle is the master's text style a shape's text falls back to: the
// title or body style for a placeholder, the presentation's default text style
// for anything else.
func (s *slideReader) textStyle(ph *xPlaceholder) *xListStyle {
	if ph == nil {
		return s.defaultText
	}
	if s.master == nil || s.master.part.TextStyles == nil {
		return nil
	}
	styles := s.master.part.TextStyles
	switch placeholderKind(ph.Type) {
	case "title":
		return styles.Title
	case "dt", "ftr", "sldNum", "hdr":
		return styles.Other
	}
	return styles.Body
}

// paragraphs converts one paragraph. A line break starts a new paragraph of
// the same style, which is how the editor breaks a line.
func (s *slideReader) paragraphs(p xParagraph, lists []*xListStyle, fontColor string) []outParagraph {
	level := 0
	if p.Props != nil {
		level = int(max(0, min(p.Props.Level, 8)))
	}
	props := []*xParaProps{p.Props}
	for _, list := range lists {
		if list != nil {
			props = append(props, list.Levels[level])
		}
	}
	runDefaults := make([]*xRunProps, 0, len(props))
	for _, pp := range props {
		if pp != nil {
			runDefaults = append(runDefaults, pp.Defaults)
		}
	}

	template := outParagraph{Runs: []outRun{}}
	for _, pp := range props {
		if pp != nil && pp.Align != "" {
			template.Align = map[string]string{
				"ctr": "center", "r": "end", "just": "justify", "dist": "justify", "justLow": "justify",
				"thaiDist": "justify",
			}[pp.Align]
			break
		}
	}
	for _, pp := range props {
		if pp == nil {
			continue
		}
		if pp.NoBullet != nil || pp.CharBullet != nil || pp.PicBullet != nil || pp.AutoNumber != nil {
			switch {
			case pp.AutoNumber != nil:
				template.List = "numbered"
			case pp.CharBullet != nil, pp.PicBullet != nil:
				template.List = "bullet"
			}
			break
		}
	}

	out := []outParagraph{cloneParagraph(template)}
	for _, run := range p.Runs {
		if run.Break {
			out = append(out, cloneParagraph(template))
			continue
		}
		if run.Text == "" {
			continue
		}
		cur := &out[len(out)-1]
		cur.Runs = append(cur.Runs, s.run(run, runDefaults, fontColor))
	}
	for i := range out {
		out[i].LineSpacing = s.lineSpacing(props, out[i].Runs, runDefaults)
	}
	return out
}

// cloneParagraph is a copy of p with runs of its own.
func cloneParagraph(p outParagraph) outParagraph {
	p.Runs = []outRun{}
	return p
}

// lineSpacing is a paragraph's line height as a multiple of its font size,
// nil at single spacing, which is the editor's default.
func (s *slideReader) lineSpacing(props []*xParaProps, runs []outRun, defaults []*xRunProps) *float64 {
	for _, pp := range props {
		if pp == nil || pp.LineSpacing == nil {
			continue
		}
		var spacing float64
		switch {
		case pp.LineSpacing.Percent != nil:
			spacing = float64(pp.LineSpacing.Percent.Val) / 100_000 * defaultLineSpacing
		case pp.LineSpacing.Points != nil:
			size := s.fontSize(defaults)
			if len(runs) > 0 && runs[0].FontSize != nil {
				size = *runs[0].FontSize
			}
			if size <= 0 {
				return nil
			}
			// Points are hundredths of a point; size is in slide units.
			spacing = float64(pp.LineSpacing.Points.Val) * emuPerHundredthPoint / s.scale / size
		default:
			continue
		}
		spacing = round(spacing)
		if spacing <= 0 || math.Abs(spacing-defaultLineSpacing) < 0.005 {
			return nil
		}
		return &spacing
	}
	return nil
}

// fontSize is the first size the run properties set, or PowerPoint's
// default, in slide units.
func (s *slideReader) fontSize(props []*xRunProps) float64 {
	hundredths := int64(defaultFontHundredths)
	for _, rp := range props {
		if rp != nil && rp.Size != nil {
			if n, err := strconv.ParseInt(strings.TrimSpace(*rp.Size), 10, 64); err == nil && n > 0 {
				hundredths = n
				break
			}
		}
	}
	return round(float64(hundredths) * emuPerHundredthPoint / s.scale)
}

// run converts a run, each style taken from the first of its own properties
// and the defaults that sets it.
func (s *slideReader) run(run xRun, defaults []*xRunProps, fontColor string) outRun {
	props := append([]*xRunProps{run.Props}, defaults...)
	out := outRun{Text: run.Text}
	size := s.fontSize(props)
	out.FontSize = &size
	first := func(get func(*xRunProps) *string) (string, bool) {
		for _, rp := range props {
			if rp != nil {
				if v := get(rp); v != nil {
					return *v, true
				}
			}
		}
		return "", false
	}
	if v, ok := first(func(rp *xRunProps) *string { return rp.Bold }); ok {
		out.Bold = v == "1" || v == "true"
	}
	if v, ok := first(func(rp *xRunProps) *string { return rp.Italic }); ok {
		out.Italic = v == "1" || v == "true"
	}
	if v, ok := first(func(rp *xRunProps) *string { return rp.Underline }); ok {
		out.Underline = v != "none"
	}
	if v, ok := first(func(rp *xRunProps) *string { return rp.Strike }); ok {
		out.Strikethrough = v != "noStrike"
	}
	out.Color = fontColor
	for _, rp := range props {
		if rp != nil && (rp.Solid != nil || rp.Gradient != nil || rp.Pattern != nil) {
			out.Color = s.fill(rp.xFill, nil)
			break
		}
	}
	for _, rp := range props {
		if rp != nil && rp.Latin != nil && rp.Latin.Typeface != "" {
			if family := s.typeface(rp.Latin.Typeface); family != "" {
				out.FontFamily = &family
			}
			break
		}
	}
	return out
}

// typeface resolves a theme font reference (+mj-lt, +mn-lt) to the theme's
// font.
func (s *slideReader) typeface(face string) string {
	switch {
	case strings.HasPrefix(face, "+mj-"):
		return s.theme.majorFont
	case strings.HasPrefix(face, "+mn-"):
		return s.theme.minorFont
	}
	return face
}
