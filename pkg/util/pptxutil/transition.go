package pptxutil

// cspell:ignore spd

import (
	"fmt"
	"math"
	"strconv"
)

// Transition durations, in milliseconds, as quark_slides keeps them.
const (
	minTransitionMs     = 200
	maxTransitionMs     = 2000
	defaultTransitionMs = 500
)

// The markup-compatibility and PowerPoint 2010 namespaces a transition's exact
// duration (p14:dur) is written under, as PowerPoint writes it.
const (
	nsMarkupCompat = "http://schemas.openxmlformats.org/markup-compatibility/2006"
	nsP14          = "http://schemas.microsoft.com/office/powerpoint/2010/main"
)

// transitionDirs maps a .qslide transition direction — the way the slides
// travel — to PresentationML's dir, which names the same thing.
var transitionDirs = map[string]string{"left": "l", "right": "r", "up": "u", "down": "d"}

// transitionXML is the slide's <p:transition>: the effect closest to t, or ""
// for none, or for a kind PowerPoint has no match for. A newer PowerPoint
// reads the exact duration from the p14 choice; an older one the nearest of
// its three speeds from the fallback.
func transitionXML(t *qslideTransition) string {
	if t == nil {
		return ""
	}
	dir, ok := transitionDirs[t.Direction]
	if !ok {
		dir = "l"
	}
	var effect string
	switch t.Kind {
	case "fade":
		effect = `<p:fade/>`
	case "push":
		effect = `<p:push dir="` + dir + `"/>`
	case "wipe":
		effect = `<p:wipe dir="` + dir + `"/>`
	case "zoom":
		effect = `<p:zoom/>`
	default:
		return ""
	}
	ms := transitionMs(t.Duration)
	spd := "slow"
	switch {
	case ms < 625:
		spd = "fast"
	case ms < 875:
		spd = "med"
	}
	return fmt.Sprintf(`<mc:AlternateContent xmlns:mc="%s">`+
		`<mc:Choice xmlns:p14="%s" Requires="p14"><p:transition spd="%s" p14:dur="%d">%s</p:transition></mc:Choice>`+
		`<mc:Fallback><p:transition spd="%s">%s</p:transition></mc:Fallback></mc:AlternateContent>`,
		nsMarkupCompat, nsP14, spd, ms, effect, spd, effect)
}

// transitionMs is a .qslide duration within the bounds the editor keeps, the
// default when it sets none.
func transitionMs(d *float64) int {
	if d == nil || math.IsNaN(*d) {
		return defaultTransitionMs
	}
	return int(math.Max(minTransitionMs, math.Min(maxTransitionMs, math.Round(*d))))
}

// readTransition maps the transitions a slide holds — its own, and those in
// mc:AlternateContent, PowerPoint 2010's own effects among them — onto the
// first a .qslide can play. mapped is false when the slide has an effect and
// none of its transitions maps; a slide with no effect is no transition.
func readTransition(part xSlidePart) (out *outTransition, mapped bool) {
	var candidates []*xTransition
	for _, alt := range part.Alternates {
		for _, c := range alt.Choices {
			candidates = append(candidates, c.Transition)
		}
		if alt.Fallback != nil {
			candidates = append(candidates, alt.Fallback.Transition)
		}
	}
	candidates = append(candidates, part.Transition)

	hasEffect := false
	duration := 0
	for _, c := range candidates {
		if c == nil {
			continue
		}
		hasEffect = hasEffect || c.Fade != nil || c.Push != nil || c.Wipe != nil || c.Zoom != nil
		for _, other := range c.Other {
			if other.XMLName.Local != "sndAc" && other.XMLName.Local != "extLst" {
				hasEffect = true
			}
		}
		if ms, err := strconv.Atoi(c.Duration); err == nil && duration == 0 {
			duration = ms
		}
	}
	for _, c := range candidates {
		if c == nil {
			continue
		}
		var t outTransition
		switch {
		case c.Fade != nil:
			t.Kind = "fade"
		case c.Push != nil:
			t.Kind, t.Direction = "push", importDirection(c.Push.Dir)
		case c.Wipe != nil:
			t.Kind, t.Direction = "wipe", importDirection(c.Wipe.Dir)
		case c.Zoom != nil:
			t.Kind = "zoom"
		default:
			continue
		}
		ms := duration
		if ms == 0 {
			// The schema's own default speed is fast.
			ms = map[string]int{"med": 750, "slow": 1000}[c.Speed]
			if ms == 0 {
				ms = 500
			}
		}
		ms = max(minTransitionMs, min(maxTransitionMs, ms))
		if ms != defaultTransitionMs {
			t.Duration = ms
		}
		return &t, true
	}
	return nil, !hasEffect
}

// importDirection is the .qslide direction for a PresentationML dir, ""
// (left, the default either side) when it is l or not one of the four.
func importDirection(dir string) string {
	for name, d := range transitionDirs {
		if d == dir && name != "left" {
			return name
		}
	}
	return ""
}
