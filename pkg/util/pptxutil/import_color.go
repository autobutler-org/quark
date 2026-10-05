package pptxutil

// cspell:ignore clr lum scrgb srgb

import (
	"fmt"
	"math"
	"strconv"
)

// theme is what an import reads of a theme: its colors by name (dk1, lt1,
// accent1, ...) as RRGGBB, and its heading and body fonts.
type theme struct {
	colors               map[string]string
	majorFont, minorFont string
}

// presetColors are the preset colors decks commonly use; one not listed
// reads as unset.
var presetColors = map[string]string{
	"black": "000000", "white": "FFFFFF", "red": "FF0000", "green": "008000", "blue": "0000FF",
	"yellow": "FFFF00", "cyan": "00FFFF", "magenta": "FF00FF", "gray": "808080", "grey": "808080",
	"orange": "FFA500", "purple": "800080", "darkGray": "A9A9A9", "lightGray": "D3D3D3",
}

// systemColors are the system colors a file without lastClr is drawn in.
var systemColors = map[string]string{"windowText": "000000", "window": "FFFFFF"}

// readTheme reads a theme's colors and fonts.
func (im *importer) readTheme(name string) (*theme, error) {
	var x xTheme
	if err := im.a.decodeXML(name, &x); err != nil {
		return nil, err
	}
	t := &theme{colors: map[string]string{}, majorFont: x.MajorFont.Typeface, minorFont: x.MinorFont.Typeface}
	for _, entry := range x.Colors.Entries {
		switch {
		case entry.RGB != nil:
			t.colors[entry.XMLName.Local] = entry.RGB.Val
		case entry.System != nil && entry.System.LastClr != "":
			t.colors[entry.XMLName.Local] = entry.System.LastClr
		case entry.System != nil:
			t.colors[entry.XMLName.Local] = systemColors[entry.System.Val]
		}
	}
	return t, nil
}

// rgba is a color with channels from 0 to 1.
type rgba struct{ r, g, b, a float64 }

// hex is a color choice as .qslide writes it — #RRGGBB, or #RRGGBBAA when it
// is not opaque — or "" when it names nothing this reader can resolve.
func (s *slideReader) hex(c *xColorChoice) string {
	col, ok := s.resolve(c)
	if !ok {
		return ""
	}
	channel := func(v float64) int { return int(math.Round(math.Max(0, math.Min(1, v)) * 255)) }
	out := fmt.Sprintf("#%02X%02X%02X", channel(col.r), channel(col.g), channel(col.b))
	if a := channel(col.a); a < 255 {
		out += fmt.Sprintf("%02X", a)
	}
	return out
}

// resolve reads a color choice, a theme color resolved through the master's
// color map and the theme, and applies its transforms.
func (s *slideReader) resolve(c *xColorChoice) (rgba, bool) {
	if c == nil {
		return rgba{}, false
	}
	var base string
	var transforms xColorTransforms
	switch {
	case c.RGB != nil:
		base, transforms = c.RGB.Val, c.RGB.xColorTransforms
	case c.Scheme != nil:
		name := c.Scheme.Val
		if mapped, ok := s.colorMap[name]; ok {
			name = mapped
		}
		base, transforms = s.theme.colors[name], c.Scheme.xColorTransforms
	case c.System != nil:
		base = c.System.LastClr
		if base == "" {
			base = systemColors[c.System.Val]
		}
		transforms = c.System.xColorTransforms
	case c.Preset != nil:
		base, transforms = presetColors[c.Preset.Val], c.Preset.xColorTransforms
	case c.ScRGB != nil:
		// scRGB is linear light in 1,000ths of a percent.
		col := rgba{
			r: srgbFromLinear(float64(c.ScRGB.R) / 100_000),
			g: srgbFromLinear(float64(c.ScRGB.G) / 100_000),
			b: srgbFromLinear(float64(c.ScRGB.B) / 100_000),
			a: 1,
		}
		return col.apply(c.ScRGB.xColorTransforms), true
	}
	col, ok := parseRGB(base)
	if !ok {
		return rgba{}, false
	}
	return col.apply(transforms), true
}

// parseRGB reads RRGGBB.
func parseRGB(hex string) (rgba, bool) {
	if len(hex) != 6 {
		return rgba{}, false
	}
	n, err := strconv.ParseUint(hex, 16, 32)
	if err != nil {
		return rgba{}, false
	}
	return rgba{r: float64(n>>16&0xFF) / 255, g: float64(n>>8&0xFF) / 255, b: float64(n&0xFF) / 255, a: 1}, true
}

// apply applies the transforms PowerPoint's color pickers write: shade and
// tint toward black and white, luminance modulation and offset in HSL, and
// alpha. Values are 1,000ths of a percent.
func (c rgba) apply(t xColorTransforms) rgba {
	frac := func(v *xValue) float64 { return float64(v.Val) / 100_000 }
	if t.Shade != nil {
		k := frac(t.Shade)
		c.r, c.g, c.b = c.r*k, c.g*k, c.b*k
	}
	if t.Tint != nil {
		k := frac(t.Tint)
		c.r, c.g, c.b = 1-(1-c.r)*k, 1-(1-c.g)*k, 1-(1-c.b)*k
	}
	if t.LumMod != nil || t.LumOff != nil {
		h, sat, l := toHSL(c)
		if t.LumMod != nil {
			l *= frac(t.LumMod)
		}
		if t.LumOff != nil {
			l += frac(t.LumOff)
		}
		c = fromHSL(h, sat, math.Max(0, math.Min(1, l)), c.a)
	}
	if t.Alpha != nil {
		c.a = math.Max(0, math.Min(1, frac(t.Alpha)))
	}
	return c
}

// srgbFromLinear gamma-encodes a linear channel.
func srgbFromLinear(v float64) float64 {
	v = math.Max(0, math.Min(1, v))
	if v <= 0.0031308 {
		return 12.92 * v
	}
	return 1.055*math.Pow(v, 1/2.4) - 0.055
}

// toHSL converts to hue (0–1), saturation and lightness.
func toHSL(c rgba) (h, s, l float64) {
	hi, lo := math.Max(c.r, math.Max(c.g, c.b)), math.Min(c.r, math.Min(c.g, c.b))
	l = (hi + lo) / 2
	if hi == lo {
		return 0, 0, l
	}
	d := hi - lo
	if l > 0.5 {
		s = d / (2 - hi - lo)
	} else {
		s = d / (hi + lo)
	}
	switch hi {
	case c.r:
		h = (c.g - c.b) / d
		if c.g < c.b {
			h += 6
		}
	case c.g:
		h = (c.b-c.r)/d + 2
	default:
		h = (c.r-c.g)/d + 4
	}
	return h / 6, s, l
}

// fromHSL converts back from toHSL's terms.
func fromHSL(h, s, l, a float64) rgba {
	if s == 0 {
		return rgba{l, l, l, a}
	}
	var q float64
	if l < 0.5 {
		q = l * (1 + s)
	} else {
		q = l + s - l*s
	}
	p := 2*l - q
	hue := func(t float64) float64 {
		t = t - math.Floor(t)
		switch {
		case t < 1.0/6:
			return p + (q-p)*6*t
		case t < 0.5:
			return q
		case t < 2.0/3:
			return p + (q-p)*(2.0/3-t)*6
		}
		return p
	}
	return rgba{hue(h + 1.0/3), hue(h), hue(h - 1.0/3), a}
}
