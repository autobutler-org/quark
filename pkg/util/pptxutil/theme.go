package pptxutil

// cspell:ignore clr fbbf srgb

import (
	"encoding/json"
	"strings"
)

// A .qslide theme, as quark_slides' SlideTheme stores it (schema version 2):
// a palette of ten color roles, a heading and a body font, and the text style
// of each text role. Elements name a role color "theme:<role>" and leave text
// styles unset to take their box's role style, so the export resolves both
// against the theme to draw the slide the editor draws.
//
// Layouts are not stored: they are quark_slides' built-in SlideMaster, and a
// placeholder text box carries the frame, anchor and alignment its slot gave
// it, and the slot's role as its textRole. So the role is all of the layout an
// export needs. The theme's shape style only seeds new shapes in the editor
// and is not read here.

// themeRolePrefix starts a role color: "theme:accent1".
const themeRolePrefix = "theme:"

// themeRoles are ThemeColor's roles, each with its fallback — its color in
// the light theme, which a role reads as with no theme at hand — and the
// PowerPoint scheme color it maps onto, in the order a scheme lists them.
var themeRoles = []struct {
	name, fallback, scheme string
}{
	{"text", "1C1B1F", "dk1"},
	{"background", "FFFFFF", "lt1"},
	{"text2", "4B5563", "dk2"},
	{"background2", "F1F3F6", "lt2"},
	{"accent1", "3366FF", "accent1"},
	{"accent2", "00A3A3", "accent2"},
	{"accent3", "F59E0B", "accent3"},
	{"accent4", "E5484D", "accent4"},
	{"accent5", "8B5CF6", "accent5"},
	{"accent6", "22C55E", "accent6"},
}

// The text role styles a theme that leaves one out has: SlideTheme's
// defaults, which the light theme uses.
var (
	defaultTitleStyle    = qslideTextStyle{FontSize: 60, Color: "theme:text", Heading: true}
	defaultSubtitleStyle = qslideTextStyle{FontSize: 40, Color: "theme:text2"}
	defaultBodyStyle     = qslideTextStyle{FontSize: defaultFontSize, Color: "theme:text"}
)

// qslideTheme is a theme as SlideTheme.fromJson reads it. Colors maps a role
// to #RRGGBB or #RRGGBBAA; a role this version does not know is ignored.
type qslideTheme struct {
	Name        string           `json:"name"`
	Colors      map[string]any   `json:"colors"`
	HeadingFont *string          `json:"headingFont"`
	BodyFont    *string          `json:"bodyFont"`
	Title       *qslideTextStyle `json:"title"`
	Subtitle    *qslideTextStyle `json:"subtitle"`
	Body        *qslideTextStyle `json:"body"`
}

// qslideTextStyle is ThemeTextStyle: a size in slide units, a color, usually a
// role, and whether the text is set in the heading font.
type qslideTextStyle struct {
	FontSize float64 `json:"fontSize"`
	Color    string  `json:"color"`
	Heading  bool    `json:"heading"`
}

// qslideThemeField is the presentation's "theme": an object since version 2,
// and in version 1 a string naming a theme by id, which QslideCodec's
// migration turns into the built-in theme of that id. Anything else is no
// theme, since what a newer writer puts there must not fail the export.
type qslideThemeField struct {
	object *qslideTheme
	ref    string
}

// UnmarshalJSON reads either form of the field.
func (f *qslideThemeField) UnmarshalJSON(b []byte) error {
	*f = qslideThemeField{}
	switch {
	case len(b) > 0 && b[0] == '{':
		f.object = &qslideTheme{}
		return json.Unmarshal(b, f.object)
	case len(b) > 0 && b[0] == '"':
		return json.Unmarshal(b, &f.ref)
	}
	return nil
}

// theme is the theme the field gives a file of schema version, or nil.
func (f qslideThemeField) theme(version int) *deckTheme {
	switch {
	case version == 1 && f.ref != "":
		if builtIn, ok := builtInThemes[f.ref]; ok {
			return newDeckTheme(builtIn)
		}
	case version >= 2 && f.object != nil:
		return newDeckTheme(*f.object)
	}
	return nil
}

// deckTheme is a theme resolved for drawing: every role's color, the fonts,
// and the three text styles.
type deckTheme struct {
	name string
	// colors maps every role to its color.
	colors                map[string]color
	headingFont, bodyFont string
	title, subtitle, body qslideTextStyle
}

// newDeckTheme resolves t as ThemePalette and SlideTheme read it: a role the
// palette leaves out — or gives a value that is not a color — is its
// fallback, and a palette entry that is itself a role color is that role's
// fallback.
func newDeckTheme(t qslideTheme) *deckTheme {
	d := &deckTheme{name: t.Name, colors: map[string]color{}}
	for _, role := range themeRoles {
		c := color{rgb: role.fallback, alpha: 1}
		if value, ok := t.Colors[role.name].(string); ok {
			if name, isRole := strings.CutPrefix(value, themeRolePrefix); isRole {
				c = fallbackColor(name)
			} else if parsed, ok := parseColor(value); ok {
				c = parsed
			}
		}
		d.colors[role.name] = c
	}
	if t.HeadingFont != nil {
		d.headingFont = strings.TrimSpace(*t.HeadingFont)
	}
	if t.BodyFont != nil {
		d.bodyFont = strings.TrimSpace(*t.BodyFont)
	}
	d.title = textStyleOr(t.Title, defaultTitleStyle)
	d.subtitle = textStyleOr(t.Subtitle, defaultSubtitleStyle)
	d.body = textStyleOr(t.Body, defaultBodyStyle)
	return d
}

// textStyleOr is s, or fallback when it is left out. A style without a usable
// size keeps the fallback's, and one without a color is in the text role, as
// ThemeTextStyle reads it.
func textStyleOr(s *qslideTextStyle, fallback qslideTextStyle) qslideTextStyle {
	if s == nil {
		return fallback
	}
	style := *s
	if style.FontSize <= 0 {
		style.FontSize = fallback.FontSize
	}
	if style.Color == "" {
		style.Color = themeRolePrefix + "text"
	}
	return style
}

// fallbackColor is a role's light-theme color; a role this version does not
// know reads as text.
func fallbackColor(name string) color {
	for _, role := range themeRoles {
		if role.name == name {
			return color{rgb: role.fallback, alpha: 1}
		}
	}
	return color{rgb: themeRoles[0].fallback, alpha: 1}
}

// resolveColor reads a .qslide color, a role resolved against theme: its
// color there, or its fallback when the deck has no theme. A role this version
// does not know reads as text, and anything else that is not a color is unset.
func resolveColor(value string, theme *deckTheme) (color, bool) {
	name, isRole := strings.CutPrefix(value, themeRolePrefix)
	if !isRole {
		return parseColor(value)
	}
	if theme == nil {
		return fallbackColor(name), true
	}
	if c, ok := theme.colors[name]; ok {
		return c, true
	}
	return theme.colors["text"], true
}

// runStyle is what a run that sets no size, family or color of its own takes
// from its text box's role. color and font are unset when there is nothing to
// write: no theme, or a theme leaving the font to the default.
type runStyle struct {
	size  float64
	color *color
	font  string
}

// roleStyle is the run style of text role in theme, as the editor's
// SlideTextLayout.forBox resolves it. A role this version does not know is
// body text. With no theme, sizes are the light theme's — a canvas draws a
// deck with none in its type — and colors and fonts inherit the package's.
func roleStyle(theme *deckTheme, role string) runStyle {
	pick := func(title, subtitle, body qslideTextStyle) qslideTextStyle {
		switch role {
		case "title":
			return title
		case "subtitle":
			return subtitle
		}
		return body
	}
	if theme == nil {
		return runStyle{size: pick(defaultTitleStyle, defaultSubtitleStyle, defaultBodyStyle).FontSize}
	}
	style := pick(theme.title, theme.subtitle, theme.body)
	out := runStyle{size: style.FontSize, font: theme.bodyFont}
	if style.Heading {
		out.font = theme.headingFont
	}
	if c, ok := resolveColor(style.Color, theme); ok {
		out.color = &c
	}
	return out
}

// builtInThemes are quark_slides' SlideThemes by id, for a version 1 file
// that names one. Each leaves out what is SlideTheme's default.
var builtInThemes = map[string]qslideTheme{
	"light": {Name: "Light"},
	"dark": {Name: "Dark", Colors: palette(
		"F3F4F6", "121318", "A9B0BC", "1F2229", "7AA2FF", "4FD1C5", "FBBF24", "FF7A80", "B69CFF", "6EE7A0")},
	"warm": {Name: "Warm", HeadingFont: ptr("Georgia"), Colors: palette(
		"3B2A20", "FFF8F0", "7A5C48", "F6E7D8", "C2410C", "B45309", "A16207", "BE123C", "9D174D", "4D7C0F")},
	"cool": {Name: "Cool", Colors: palette(
		"0F2533", "F4F8FB", "44606F", "E2ECF3", "0E7490", "1D4ED8", "0369A1", "4338CA", "0F766E", "64748B")},
	"highContrast": {
		Name: "High contrast",
		Colors: palette(
			"FFFFFF", "000000", "FFFF00", "1A1A1A", "FFD400", "00E5FF", "FF6EC7", "7CFF4F", "FFFFFF", "FF9F1C"),
		Title:    &qslideTextStyle{FontSize: 64, Color: "theme:text", Heading: true},
		Subtitle: &qslideTextStyle{FontSize: 44, Color: "theme:text2"},
		Body:     &qslideTextStyle{FontSize: 40, Color: "theme:text"},
	},
}

// palette is a theme's colors, RRGGBB in themeRoles' order.
func palette(rgb ...string) map[string]any {
	colors := map[string]any{}
	for i, role := range themeRoles {
		colors[role.name] = "#" + rgb[i]
	}
	return colors
}

func ptr[T any](v T) *T { return &v }
