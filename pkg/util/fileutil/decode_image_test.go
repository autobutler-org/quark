package fileutil

import (
	"bytes"
	"encoding/binary"
	"errors"
	"hash/crc32"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/photoutil"
)

// A ?format=jpeg download decodes the whole image, so it refuses one whose
// header claims more than the pixel cap before a pixel is allocated (#2762).
func TestDecodeImage_RefusesPixelsOverTheCap(t *testing.T) {
	// A PNG signature and an IHDR claiming 9000 × 9000 8-bit grayscale: all
	// a decoder reads before sizing its buffer.
	var data bytes.Buffer
	data.WriteString("\x89PNG\r\n\x1a\n")
	ihdr := []byte("IHDR")
	ihdr = binary.BigEndian.AppendUint32(ihdr, 9000)
	ihdr = binary.BigEndian.AppendUint32(ihdr, 9000)
	ihdr = append(ihdr, 8, 0, 0, 0, 0)
	_ = binary.Write(&data, binary.BigEndian, uint32(len(ihdr)-4))
	data.Write(ihdr)
	_ = binary.Write(&data, binary.BigEndian, crc32.ChecksumIEEE(ihdr))

	if _, err := DecodeImage(&data); !errors.Is(err, photoutil.ErrImageTooLarge) {
		t.Fatalf("DecodeImage = %v, want photoutil.ErrImageTooLarge", err)
	}
}
