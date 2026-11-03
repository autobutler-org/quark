package photoutil

import (
	"bytes"
	"context"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"path"
	"strings"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// ErrRotationUnsupported is [RotatePhoto] declining a file it cannot turn
// losslessly: anything but a JPEG, or a JPEG whose EXIF has no Orientation
// tag to patch. Handlers answer it as 422.
var ErrRotationUnsupported = errors.New("rotation not supported for this format")

// exifOrientationTag is the EXIF tag number of Orientation.
const exifOrientationTag = 0x0112

// RotatePhotoParams names the photo to turn and by how much.
type RotatePhotoParams struct {
	Ctx context.Context
	// Registry holds one namespace per device; the photo is turned in Serial's.
	Registry vfs.Registry
	// EventBus hears about the changed file. Nil publishes nothing.
	EventBus *eventbus.Bus
	// Serial is the device the photo is on, empty for the internal drive.
	Serial string
	// RelPath is the photo's path on that device.
	RelPath string
	// Quarters is how many quarter turns clockwise to add to what the photo
	// shows now. Any integer: 5 is 1, and -1 is 3.
	Quarters int64
}

// RotatePhotoResult is the photo's orientation once it is turned.
type RotatePhotoResult struct {
	// Orientation is the EXIF Orientation value (1-8) the file now carries.
	Orientation int
}

// RotatePhoto turns a JPEG by rewriting its EXIF Orientation tag rather than
// its pixels, so it is lossless and costs the same for any file size (#1014).
// The tag is overwritten in place when the file has one; a JPEG without EXIF
// gets a minimal APP1 segment streamed in through [vfs.VFS.Write], which
// swaps the file in whole. Every decoder here, and browsers and Flutter,
// already honor the tag, so thumbnails and the viewer follow the file.
//
// Anything but a JPEG is [ErrRotationUnsupported]: libheif ignores the EXIF
// tag in favor of the container's own rotation box (#1798), and there is no WebP
// encoder. A missing photo is [vfs.ErrNotFound].
func RotatePhoto(params RotatePhotoParams) (RotatePhotoResult, error) {
	fsys, err := DeviceFS(params.Registry, params.Serial)
	if err != nil {
		return RotatePhotoResult{}, err
	}
	rel := accessutil.Canonical(params.RelPath)
	if ext := strings.ToLower(path.Ext(rel)); ext != ".jpg" && ext != ".jpeg" {
		return RotatePhotoResult{}, fmt.Errorf("%w: %s", ErrRotationUnsupported, ext)
	}
	info, err := fsys.Stat(params.Ctx, rel)
	if err != nil {
		return RotatePhotoResult{}, err
	}
	src, err := fsys.Open(params.Ctx, rel)
	if err != nil {
		return RotatePhotoResult{}, err
	}
	defer src.Close()

	found, err := findJPEGOrientation(src)
	if err != nil {
		return RotatePhotoResult{}, err
	}
	// ponytail: read-modify-write is not locked; two rotates at once can lose
	// a turn. Lock per path if that ever shows up.
	next := NextOrientation(found.value, params.Quarters)
	if next != found.value {
		if err := writeOrientation(params.Ctx, fsys, src, rel, info.Size, found, next); err != nil {
			return RotatePhotoResult{}, err
		}
		if params.EventBus != nil {
			params.EventBus.Publish(eventbus.Event{Kind: eventbus.EventUpload, Path: rel, DeviceSerial: params.Serial})
		}
	}
	return RotatePhotoResult{Orientation: next}, nil
}

// NextOrientation is the EXIF orientation of a photo stored with orientation
// from after it is turned quarters quarter turns clockwise on screen. A value
// outside 1-8 reads as upright. The four turns of a plain photo walk
// 1, 6, 3, 8 and a mirrored one's walk 2, 7, 4, 5.
func NextOrientation(from int, quarters int64) int {
	cycle := []int{1, 6, 3, 8}
	if from == 2 || from == 4 || from == 5 || from == 7 {
		cycle = []int{2, 7, 4, 5}
	}
	at := 0
	for i, o := range cycle {
		if o == from {
			at = i
		}
	}
	return cycle[(int64(at)+quarters%4+4)%4]
}

// jpegOrientation is where a JPEG keeps its orientation.
type jpegOrientation struct {
	// present is whether an Orientation tag exists to patch.
	present bool
	// value is the tag's value, 1 when there is none.
	value int
	// at is the file offset of the tag's 2-byte value.
	at int64
	// order is the byte order of the EXIF block.
	order interface {
		binary.ByteOrder
		binary.AppendByteOrder
	}
	// insertAt is where a new APP1 segment goes: after SOI, and after a leading
	// APP0 that must stay first.
	insertAt int64
}

// findJPEGOrientation walks the segment headers of a JPEG up to the scan,
// reading only the Exif APP1 segment, which is at most 64 KiB. A file that is
// not a JPEG, or an EXIF block with no Orientation tag to patch, is
// [ErrRotationUnsupported].
func findJPEGOrientation(r io.ReaderAt) (jpegOrientation, error) {
	notJPEG := fmt.Errorf("%w: not a JPEG", ErrRotationUnsupported)
	found := jpegOrientation{value: 1, insertAt: 2}
	var soi [2]byte
	if _, err := r.ReadAt(soi[:], 0); err != nil || soi != [2]byte{0xFF, 0xD8} {
		return found, notJPEG
	}
	for off := int64(2); ; {
		var h [4]byte
		if _, err := r.ReadAt(h[:], off); err != nil || h[0] != 0xFF {
			return found, notJPEG
		}
		marker := h[1]
		switch {
		case marker == 0xDA || marker == 0xD9:
			return found, nil // the scan or the end: no EXIF
		case marker == 0xFF:
			off++ // fill byte
			continue
		case marker == 0x01 || marker >= 0xD0 && marker <= 0xD8:
			off += 2 // standalone marker, no length
			continue
		}
		length := int64(binary.BigEndian.Uint16(h[2:]))
		if length < 2 {
			return found, notJPEG
		}
		if marker == 0xE0 && off == found.insertAt {
			found.insertAt = off + 2 + length
		}
		if marker == 0xE1 {
			payload := make([]byte, length-2)
			if _, err := r.ReadAt(payload, off+4); err != nil {
				return found, notJPEG
			}
			if bytes.HasPrefix(payload, []byte("Exif\x00\x00")) {
				return locateOrientation(payload[6:], off+4+6, found)
			}
		}
		off += 2 + length
	}
}

// locateOrientation finds the Orientation entry in IFD0 of the TIFF block
// tiff, which starts at file offset base.
func locateOrientation(tiff []byte, base int64, found jpegOrientation) (jpegOrientation, error) {
	bad := fmt.Errorf("%w: no Orientation tag in the EXIF", ErrRotationUnsupported)
	if len(tiff) < 8 {
		return found, bad
	}
	switch string(tiff[:2]) {
	case "II":
		found.order = binary.LittleEndian
	case "MM":
		found.order = binary.BigEndian
	default:
		return found, bad
	}
	ifd := int64(found.order.Uint32(tiff[4:8]))
	if ifd+2 > int64(len(tiff)) {
		return found, bad
	}
	for i := range int64(found.order.Uint16(tiff[ifd:])) {
		e := ifd + 2 + 12*i
		if e+12 > int64(len(tiff)) {
			break
		}
		entry := tiff[e : e+12]
		// A SHORT, count 1: its value sits in the entry itself.
		if found.order.Uint16(entry) == exifOrientationTag &&
			found.order.Uint16(entry[2:]) == 3 && found.order.Uint32(entry[4:]) == 1 {
			found.present = true
			found.value = int(found.order.Uint16(entry[8:]))
			found.at = base + e + 8
			return found, nil
		}
	}
	return found, bad
}

// writeOrientation stores orientation in the JPEG at rel: over the existing
// tag in place, or in a new APP1 segment when the file has no EXIF.
func writeOrientation(ctx context.Context, fsys vfs.VFS, src vfs.File, rel string, size int64, found jpegOrientation, orientation int) error {
	if found.present {
		value := found.order.AppendUint16(nil, uint16(orientation))
		if w, ok := fsys.(vfs.WriterAt); ok {
			return w.WriteAt(ctx, rel, value, found.at)
		}
		// No in-place write here: stream the file through with the two bytes
		// swapped.
		return fsys.Write(ctx, rel, io.MultiReader(
			io.NewSectionReader(src, 0, found.at),
			bytes.NewReader(value),
			io.NewSectionReader(src, found.at+2, size-found.at-2),
		), vfs.WriteOptions{})
	}
	return fsys.Write(ctx, rel, io.MultiReader(
		io.NewSectionReader(src, 0, found.insertAt),
		bytes.NewReader(orientationSegment(orientation)),
		io.NewSectionReader(src, found.insertAt, size-found.insertAt),
	), vfs.WriteOptions{})
}

// orientationSegment is an APP1 segment holding a big-endian EXIF block with
// one IFD0 entry, Orientation.
func orientationSegment(orientation int) []byte {
	seg := []byte{0xFF, 0xE1, 0, 34}
	seg = append(seg, "Exif\x00\x00MM\x00\x2A\x00\x00\x00\x08"...)
	seg = binary.BigEndian.AppendUint16(seg, 1) // one entry
	seg = binary.BigEndian.AppendUint16(seg, exifOrientationTag)
	seg = binary.BigEndian.AppendUint16(seg, 3) // SHORT
	seg = binary.BigEndian.AppendUint32(seg, 1) // count
	seg = binary.BigEndian.AppendUint16(seg, uint16(orientation))
	seg = binary.BigEndian.AppendUint16(seg, 0)  // value padding
	return binary.BigEndian.AppendUint32(seg, 0) // no next IFD
}
