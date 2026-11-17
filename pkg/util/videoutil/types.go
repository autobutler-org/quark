package videoutil

import (
	"context"
	"errors"
	"io"

	"github.com/autobutler-org/quark/pkg/vfs"
	"github.com/autobutler-org/sprocket/pkg/sprocket"
)

// maxFreeNameAttempts bounds how many names PlaceUnderFreeName tries. Each
// taken name costs one attempt, since nothing checks a name ahead of writing
// it.
const maxFreeNameAttempts = 1000

// formatSpec is one Format: the sprocket container it names and its display
// label.
type formatSpec struct {
	container sprocket.Container
	label     string
}

// formatSpecs is the one table of formats Remux writes, and so the one the
// formats endpoint, the transcode job, and Trim read. Its order is the order
// clients list them. A container sprocket learns to write is one line here.
var formatSpecs = []formatSpec{
	{container: sprocket.MP4, label: "MP4"},
	{container: sprocket.MOV, label: "MOV"},
	{container: sprocket.MKV, label: "MKV"},
	{container: sprocket.WebM, label: "WebM"},
	{container: sprocket.M4V, label: "M4V"},
	{container: sprocket.ThreeGP, label: "3GP"},
	{container: sprocket.ThreeG2, label: "3G2"},
	{container: sprocket.TS, label: "TS"},
}

// ffprobeCodecNames maps the sprocket codec names that differ from ffprobe's
// to ffprobe's, which the metadata endpoint has always returned. sprocket
// reports a codec off its short list by its four-character sample entry code.
var ffprobeCodecNames = map[string]string{
	"ac-3": "ac3",
	"ec-3": "eac3",
	"fLaC": "flac",
	"samr": "amr_nb",
	"sawb": "amr_wb",
}

// progressWriter is the output of a Trim or Remux. It stops the write once
// ctx is done, since sprocket takes no context, and reports how far through
// the source the output has got: a remux writes about as many bytes as it
// reads.
type progressWriter struct {
	ctx        context.Context
	w          io.Writer
	total      int64
	written    int64
	onProgress func(float64)
}

func (p *progressWriter) Write(b []byte) (int, error) {
	if err := p.ctx.Err(); err != nil {
		return 0, err
	}
	n, err := p.w.Write(b)
	p.written += int64(n)
	if p.onProgress != nil && p.total > 0 {
		p.onProgress(min(float64(p.written)/float64(p.total), 1))
	}
	return n, err
}

// errDryRunDone is what dryRunWriter answers the first write with: sprocket
// got as far as writing, so it accepts the source for that format.
var errDryRunDone = errors.New("dry run reached the first write")

// dryRunWriter is the output of writable's Remux. It refuses the first write,
// which stops the remux once sprocket has checked the source and before it
// copies any payload.
type dryRunWriter struct{}

func (dryRunWriter) Write([]byte) (int, error) {
	return 0, errDryRunDone
}

// readRecorder is a source file that remembers the first read of it that
// failed, other than at the end. sprocket reports a read that failed while it
// sniffed the container as ErrUnsupportedContainer, which would tell the user
// a file the disk could not read is not a video (#3427).
type readRecorder struct {
	vfs.File
	err error
}

func (r *readRecorder) Read(p []byte) (int, error) {
	n, err := r.File.Read(p)
	r.record(err)
	return n, err
}

func (r *readRecorder) ReadAt(p []byte, off int64) (int, error) {
	n, err := r.File.ReadAt(p, off)
	r.record(err)
	return n, err
}

func (r *readRecorder) record(err error) {
	if r.err == nil && err != nil && !errors.Is(err, io.EOF) {
		r.err = err
	}
}
