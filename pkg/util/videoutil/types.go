package videoutil

import (
	"context"
	"io"

	"github.com/autobutler-org/sprocket/pkg/sprocket"
)

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
