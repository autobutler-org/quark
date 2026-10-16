package audiotagutil

import (
	"bytes"
	"errors"
	"testing"
)

// FuzzRead feeds mutated files of every format through Read and ReadPicture.
// The seed corpus is built in corpus(), so `go test` runs every seed as a
// regular test; `go test -fuzz=FuzzRead ./pkg/util/audiotagutil` explores
// from there. Only the tag library runs under recover(), so a panic in this
// package's own readers fails the fuzz run.
func FuzzRead(f *testing.F) {
	for _, b := range corpus() {
		f.Add(b)
	}
	f.Fuzz(func(t *testing.T, b []byte) {
		res, err := Read(ReadParams{File: bytes.NewReader(b), Size: int64(len(b))})
		if err != nil {
			if !errors.Is(err, ErrUnsupported) && !errors.Is(err, ErrTagTooLarge) && !errors.Is(err, ErrMalformed) {
				t.Fatalf("Read returned an unclassified error: %v", err)
			}
			return
		}
		if res.Tags.Duration < 0 {
			t.Fatalf("negative duration %v", res.Tags.Duration)
		}
		pic, err := ReadPicture(ReadPictureParams{File: bytes.NewReader(b), Size: int64(len(b))})
		switch {
		case res.Tags.Picture == nil:
			if !errors.Is(err, ErrNoPicture) {
				t.Fatalf("ReadPicture = %v with no picture in Read", err)
			}
		case err != nil:
			t.Fatalf("ReadPicture: %v after Read found a picture", err)
		case int64(len(pic.Data)) != res.Tags.Picture.Size || res.Tags.Picture.Size > MaxTagBytes:
			t.Fatalf("picture is %d bytes, Read said %d", len(pic.Data), res.Tags.Picture.Size)
		}
	})
}

func TestCorpusReadsCleanly(t *testing.T) {
	for name, b := range corpus() {
		res, err := Read(ReadParams{File: bytes.NewReader(b), Size: int64(len(b))})
		if err != nil {
			t.Errorf("%s: Read: %v", name, err)
			continue
		}
		if res.Tags.Title == "" && name != "aac" {
			t.Errorf("%s: no title in %+v", name, res.Tags)
		}
	}
}
