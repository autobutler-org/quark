package videoutil

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"time"

	"github.com/autobutler-org/sprocket/pkg/sprocket"
)

// probe opens filePath and runs sprocket's Probe over it.
func probe(filePath string) (sprocket.Info, error) {
	f, err := os.Open(filePath)
	if err != nil {
		return sprocket.Info{}, err
	}
	defer f.Close()
	stat, err := f.Stat()
	if err != nil {
		return sprocket.Info{}, err
	}
	info, err := sprocket.Probe(f, stat.Size())
	if err != nil {
		return sprocket.Info{}, fmt.Errorf("probe %s: %w", filepath.Base(filePath), err)
	}
	return info, nil
}

// writeFrom opens source and creates output, hands both to write, and removes
// output again if write fails, so a failed or canceled run leaves nothing
// behind.
func writeFrom(ctx context.Context, source, output string, onProgress func(float64), write func(src *os.File, size int64, w *progressWriter) error) (err error) {
	src, err := os.Open(source)
	if err != nil {
		return err
	}
	defer src.Close()
	stat, err := src.Stat()
	if err != nil {
		return err
	}
	out, err := os.Create(output)
	if err != nil {
		return err
	}
	defer func() {
		err = errors.Join(err, out.Close())
		if err != nil {
			_ = os.Remove(output)
		}
	}()
	return write(src, stat.Size(), &progressWriter{ctx: ctx, w: out, total: stat.Size(), onProgress: onProgress})
}

// lookupFormat finds f's row in formatSpecs.
func lookupFormat(f Format) (formatSpec, bool) {
	i := slices.IndexFunc(formatSpecs, func(spec formatSpec) bool { return Format(spec.container) == f })
	if i < 0 {
		return formatSpec{}, false
	}
	return formatSpecs[i], true
}

// formatOf is the Format path's extension names, which may not be Valid.
func formatOf(path string) Format {
	return Format(strings.ToLower(strings.TrimPrefix(filepath.Ext(path), ".")))
}

// pairingWritten reports whether sprocket writes a target container from a
// source of format own at all. CanRemux speaks only for the codecs, and
// sprocket writes no Matroska or WebM from a transport stream and no
// transport stream from either of those.
// ponytail: keyed on the extension because sprocket.Info does not name the
// source container; drop this once CanRemux takes the source into account.
func pairingWritten(own Format, target sprocket.Container) bool {
	transport := own == "ts" || own == "m2ts" || own == "mts"
	matroska := own == "mkv" || own == "webm"
	switch target {
	case sprocket.MKV, sprocket.WebM:
		return !transport
	case sprocket.TS:
		return !matroska
	}
	return true
}

// ffprobeCodecName translates a sprocket codec name into ffprobe's.
func ffprobeCodecName(name string) string {
	if mapped, ok := ffprobeCodecNames[name]; ok {
		return mapped
	}
	return name
}

// counterclockwise turns sprocket's clockwise rotation into the
// counterclockwise degrees ffprobe's display matrix reports, normalized to
// [0, 360): a phone's portrait video is 90 in one and 270 in the other.
func counterclockwise(clockwise int) int {
	return (360 - clockwise%360) % 360
}

// formatTimestamp converts a Duration to an ffmpeg timestamp string (HH:MM:SS.mmm).
func formatTimestamp(d time.Duration) string {
	h := int(d.Hours())
	m := int(d.Minutes()) % 60
	s := int(d.Seconds()) % 60
	ms := int(d.Milliseconds()) % 1000
	return fmt.Sprintf("%02d:%02d:%02d.%03d", h, m, s, ms)
}
