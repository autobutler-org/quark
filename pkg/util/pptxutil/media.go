package pptxutil

import (
	"archive/zip"
	"bytes"
	"fmt"
	"image"
	"io"

	// The formats PowerPoint shows, registered for image.DecodeConfig.
	_ "image/gif"
	_ "image/jpeg"
	_ "image/png"

	// BMP, which PowerPoint shows too, registered for image.DecodeConfig.
	_ "golang.org/x/image/bmp"
)

// maxImageHeaderBytes bounds what reading a picture's header may consume. The
// header is kept, to be written ahead of the rest of the picture.
const maxImageHeaderBytes = 1 << 20 // 1 MiB

// imageExtensions maps the format image.DecodeConfig names to the media
// extension, which is also its image/ content subtype.
var imageExtensions = map[string]string{"png": "png", "jpeg": "jpeg", "gif": "gif", "bmp": "bmp"}

// embedAll embeds every picture slide shows that is not in the package yet:
// its background image, then its pictures, grouped ones included.
func (e *exporter) embedAll(slide qslideSlide) error {
	if slide.Background != nil && slide.Background.Image != "" {
		if _, err := e.embed(slide.Background.Image); err != nil {
			return err
		}
	}
	return e.embedElements(slide.Elements, 0)
}

func (e *exporter) embedElements(elements []qslideElement, depth int) error {
	if depth > MaxGroupDepth {
		return fmt.Errorf("%w: groups nest more than %d deep", ErrTooLarge, MaxGroupDepth)
	}
	for _, el := range elements {
		e.elements++
		if e.elements > MaxElements {
			return fmt.Errorf("%w: the presentation holds more than %d elements", ErrTooLarge, MaxElements)
		}
		switch el.Type {
		case typeImage:
			if _, err := e.embed(el.Source); err != nil {
				return err
			}
		case typeGroup:
			if err := e.embedElements(el.Children, depth+1); err != nil {
				return err
			}
		case typeTable:
			// A cell is drawn as a shape is, so the deck's budget pays for
			// it.
			e.elements += min(len(el.Rows)*len(el.Columns), maxTableCells)
			if e.elements > MaxElements {
				return fmt.Errorf("%w: the presentation holds more than %d elements", ErrTooLarge, MaxElements)
			}
		}
	}
	return nil
}

// embed returns the part holding the picture at source, copying it into the
// package the first time it is seen, or nil when it cannot be embedded. Only a
// failure to write the package is an error.
func (e *exporter) embed(source string) (*mediaPart, error) {
	if part, seen := e.media[source]; seen {
		return part, nil
	}
	part, err := e.copyImage(source)
	e.media[source] = part
	if part == nil {
		e.result.MissingPictures++
	} else {
		e.result.Pictures++
	}
	return part, err
}

// copyImage opens the picture, reads its header for its format and size, and
// streams it into ppt/media. A picture that will not open, is not a format
// PowerPoint shows, or is past the size limits comes back nil.
func (e *exporter) copyImage(source string) (*mediaPart, error) {
	if e.openImage == nil || source == "" {
		return nil, nil
	}
	rc, size, err := e.openImage(source)
	if err != nil {
		return nil, nil
	}
	defer rc.Close()
	if size <= 0 || size > MaxImageBytes || e.mediaBytes+size > MaxMediaBytes {
		return nil, nil
	}

	var head bytes.Buffer
	config, format, err := image.DecodeConfig(io.TeeReader(io.LimitReader(rc, maxImageHeaderBytes), &head))
	ext, ok := imageExtensions[format]
	if err != nil || !ok || config.Width <= 0 || config.Height <= 0 {
		return nil, nil
	}

	part := &mediaPart{
		name:   fmt.Sprintf("image%d.%s", e.result.Pictures+1, ext),
		width:  config.Width,
		height: config.Height,
	}
	// A picture is compressed already, but it is deflated anyway, at the
	// writer's fastest level: an entry stored as it streams needs a data
	// descriptor, and LibreOffice will not open a package with a stored entry
	// that has one.
	w, err := e.zw.CreateHeader(&zip.FileHeader{Name: "ppt/media/" + part.name, Method: zip.Deflate})
	if err != nil {
		return nil, err
	}
	if _, err := w.Write(head.Bytes()); err != nil {
		return nil, err
	}
	// The size was checked when the picture opened; a file that grows while
	// it is copied is cut off one byte past the limit and fails the export,
	// since the entry is already half written.
	copied, err := io.Copy(w, io.LimitReader(rc, MaxImageBytes-int64(head.Len())+1))
	if err != nil {
		return nil, err
	}
	total := int64(head.Len()) + copied
	if total > MaxImageBytes {
		return nil, fmt.Errorf("%w: %s grew past %d bytes while it was exported", ErrTooLarge, source, MaxImageBytes)
	}
	e.mediaBytes += total
	e.imageExts[ext] = true
	return part, nil
}
