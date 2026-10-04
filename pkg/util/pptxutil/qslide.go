package pptxutil

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"regexp"
	"strconv"
	"strings"
)

// schemaVersion is the newest .qslide schema this writer reads, the one
// quark_slides' QslideCodec writes.
const schemaVersion = 1

// The element types and shape kinds this writer draws.
const (
	typeText  = "text"
	typeShape = "shape"
	typeImage = "image"
	typeLine  = "line"
	typeGroup = "group"
)

// hexColor is a .qslide color: #RRGGBB, or #RRGGBBAA with alpha.
var hexColor = regexp.MustCompile(`^#([0-9a-fA-F]{6})([0-9a-fA-F]{2})?$`)

// qslideHeader is what a slide needs to know about the presentation before it
// can be written.
type qslideHeader struct {
	title     string
	size      qslideSize
	version   bool
	sizeKnown bool
}

// walkQslide steps through the presentation object, hands each slide to emit
// one at a time, and returns the header.
//
// The editor writes schemaVersion and size ahead of slides. A file that puts
// them after has the slides read before them held until they arrive — or until
// the end, when a missing size is the 16:9 default — since a slide cannot be
// placed without its size.
func walkQslide(dec *json.Decoder, emit func(qslideHeader, qslideSlide) error) (qslideHeader, error) {
	header := qslideHeader{size: qslideSize{Width: 1920, Height: 1080}}
	var pending []qslideSlide
	if err := expectDelim(dec, '{'); err != nil {
		return header, err
	}
	for dec.More() {
		key, err := dec.Token()
		if err != nil {
			return header, qslideError(err)
		}
		switch key {
		case "schemaVersion":
			var v json.Number
			if err := dec.Decode(&v); err != nil {
				return header, qslideError(err)
			}
			n, err := strconv.Atoi(v.String())
			if err != nil || n < 1 {
				return header, fmt.Errorf("%w: schemaVersion is not a positive integer", ErrNotQslide)
			}
			if n > schemaVersion {
				return header, fmt.Errorf("%w: written by schema version %d; this export reads up to %d",
					ErrNotQslide, n, schemaVersion)
			}
			header.version = true
		case "title":
			if err := dec.Decode(&header.title); err != nil {
				return header, qslideError(err)
			}
		case "size":
			if err := dec.Decode(&header.size); err != nil {
				return header, qslideError(err)
			}
			if header.size.Width <= 0 || header.size.Height <= 0 {
				return header, fmt.Errorf("%w: a slide size must be positive", ErrNotQslide)
			}
			header.sizeKnown = true
		case "slides":
			if err := expectDelim(dec, '['); err != nil {
				return header, err
			}
			for dec.More() {
				var slide qslideSlide
				if err := dec.Decode(&slide); err != nil {
					return header, qslideError(err)
				}
				if !header.version || !header.sizeKnown {
					pending = append(pending, slide)
					continue
				}
				if err := emitAll(header, &pending, emit); err != nil {
					return header, err
				}
				if err := emit(header, slide); err != nil {
					return header, err
				}
			}
			if err := expectDelim(dec, ']'); err != nil {
				return header, err
			}
		default:
			var skip json.RawMessage
			if err := dec.Decode(&skip); err != nil {
				return header, qslideError(err)
			}
		}
	}
	if err := expectDelim(dec, '}'); err != nil {
		return header, err
	}
	if !header.version {
		return header, fmt.Errorf("%w: no schemaVersion", ErrNotQslide)
	}
	return header, emitAll(header, &pending, emit)
}

// emitAll hands every held slide to emit and empties the list.
func emitAll(header qslideHeader, pending *[]qslideSlide, emit func(qslideHeader, qslideSlide) error) error {
	for _, slide := range *pending {
		if err := emit(header, slide); err != nil {
			return err
		}
	}
	*pending = nil
	return nil
}

// UnmarshalJSON reads an element of a known type whole, and of any other type
// only its type, as quark_slides keeps one it does not know verbatim.
func (e *qslideElement) UnmarshalJSON(b []byte) error {
	var head struct {
		Type string `json:"type"`
	}
	if err := json.Unmarshal(b, &head); err != nil {
		return err
	}
	switch head.Type {
	case typeText, typeShape, typeImage, typeLine, typeGroup:
		type plain qslideElement
		return json.Unmarshal(b, (*plain)(e))
	}
	*e = qslideElement{Type: head.Type}
	return nil
}

// expectDelim reads the next token and fails unless it is want.
func expectDelim(dec *json.Decoder, want json.Delim) error {
	tok, err := dec.Token()
	if err != nil {
		return qslideError(err)
	}
	if tok != want {
		return fmt.Errorf("%w: expected %q", ErrNotQslide, want)
	}
	return nil
}

// qslideError tells a source past [MaxQslideBytes], which the cappedReader
// reports through the decoder, from one that is not a .qslide at all.
func qslideError(err error) error {
	if errors.Is(err, ErrTooLarge) {
		return err
	}
	return fmt.Errorf("%w: %v", ErrNotQslide, err)
}

func (c *cappedReader) Read(p []byte) (int, error) {
	if c.remaining <= 0 {
		// One byte past the cap is what tells a document that is too large
		// from one that fills it exactly.
		var probe [1]byte
		if n, _ := c.r.Read(probe[:]); n > 0 {
			return 0, fmt.Errorf("%w: the presentation is larger than %d bytes", ErrTooLarge, MaxQslideBytes)
		}
		return 0, io.EOF
	}
	if int64(len(p)) > c.remaining {
		p = p[:c.remaining]
	}
	n, err := c.r.Read(p)
	c.remaining -= int64(n)
	return n, err
}

// parseColor reads a .qslide color. One that is not #RRGGBB or #RRGGBBAA is
// treated as unset.
func parseColor(hex string) (color, bool) {
	m := hexColor.FindStringSubmatch(hex)
	if m == nil {
		return color{}, false
	}
	alpha := 1.0
	if m[2] != "" {
		a, _ := strconv.ParseUint(m[2], 16, 8)
		alpha = float64(a) / 255
	}
	return color{rgb: strings.ToUpper(m[1]), alpha: alpha}, true
}
