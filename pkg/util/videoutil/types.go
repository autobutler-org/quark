package videoutil

import "sync"

// cappedBuffer keeps the first max bytes written to it and silently discards
// the rest, so a chatty ffmpeg cannot grow the error message without bound.
type cappedBuffer struct {
	buf []byte
	max int
}

// Write always reports the full length so the process writing to it never
// sees a short write.
func (b *cappedBuffer) Write(p []byte) (int, error) {
	if room := b.max - len(b.buf); room > 0 {
		b.buf = append(b.buf, p[:min(room, len(p))]...)
	}
	return len(p), nil
}

// available caches AvailableFormats' answer once ffmpeg has given one.
var (
	availableMu sync.Mutex
	available   []Format
)

// codecSpec is one encoder and its options at each Quality.
type codecSpec struct {
	encoder  string
	original []string
	small    []string
}

// formatSpec is everything Transcode needs to write one Format: its display
// label, the -f muxer (which is not always the extension), the encoders it
// re-encodes with, and the ffprobe codec names its container takes as-is.
type formatSpec struct {
	format    Format
	label     string
	muxer     string
	video     codecSpec
	audio     codecSpec
	copyVideo []string
	copyAudio []string
}

// The encoders the format table uses. CRF encoders take a constant quality;
// the older MPEG-family ones take a quantizer, where lower is better.
var (
	h264   = codecSpec{encoder: "libx264", original: []string{"-crf", "20", "-preset", "fast"}, small: []string{"-crf", "28", "-preset", "fast"}}
	aac    = codecSpec{encoder: "aac", original: []string{"-b:a", "192k"}, small: []string{"-b:a", "96k"}}
	vp9    = codecSpec{encoder: "libvpx-vp9", original: []string{"-crf", "31", "-b:v", "0", "-row-mt", "1"}, small: []string{"-crf", "40", "-b:v", "0", "-row-mt", "1"}}
	opus   = codecSpec{encoder: "libopus", original: []string{"-b:a", "128k"}, small: []string{"-b:a", "64k"}}
	theora = codecSpec{encoder: "libtheora", original: []string{"-q:v", "7"}, small: []string{"-q:v", "4"}}
	vorbis = codecSpec{encoder: "libvorbis", original: []string{"-q:a", "5"}, small: []string{"-q:a", "2"}}
	mpeg4  = codecSpec{encoder: "mpeg4", original: []string{"-q:v", "3"}, small: []string{"-q:v", "8"}}
	mp3    = codecSpec{encoder: "libmp3lame", original: []string{"-b:a", "192k"}, small: []string{"-b:a", "96k"}}
	wmv2   = codecSpec{encoder: "wmv2", original: []string{"-q:v", "3"}, small: []string{"-q:v", "8"}}
	wmav2  = codecSpec{encoder: "wmav2", original: []string{"-b:a", "192k"}, small: []string{"-b:a", "96k"}}
	mpeg2  = codecSpec{encoder: "mpeg2video", original: []string{"-q:v", "3"}, small: []string{"-q:v", "8"}}
	mp2    = codecSpec{encoder: "mp2", original: []string{"-b:a", "192k"}, small: []string{"-b:a", "96k"}}
)

// formatSpecs is the one table of video formats Transcode writes: every video
// extension storageutil recognizes. Its order is the order clients list them.
// The copy lists are deliberately conservative; a codec left off only costs a
// re-encode, while one wrongly on fails the job.
var formatSpecs = []formatSpec{
	{format: "mp4", label: "MP4", muxer: "mp4", video: h264, audio: aac, copyVideo: []string{"h264", "hevc"}, copyAudio: []string{"aac", "mp3"}},
	{format: "mov", label: "MOV", muxer: "mov", video: h264, audio: aac, copyVideo: []string{"h264", "hevc"}, copyAudio: []string{"aac", "mp3"}},
	{format: "mkv", label: "MKV", muxer: "matroska", video: h264, audio: aac,
		copyVideo: []string{"h264", "hevc", "vp8", "vp9", "av1", "mpeg4", "mpeg2video", "theora"},
		copyAudio: []string{"aac", "mp3", "mp2", "opus", "vorbis", "ac3", "flac"}},
	{format: "webm", label: "WebM", muxer: "webm", video: vp9, audio: opus, copyVideo: []string{"vp8", "vp9", "av1"}, copyAudio: []string{"opus", "vorbis"}},
	{format: "avi", label: "AVI", muxer: "avi", video: mpeg4, audio: mp3, copyVideo: []string{"mpeg4"}, copyAudio: []string{"mp3"}},
	{format: "m4v", label: "M4V", muxer: "ipod", video: h264, audio: aac, copyVideo: []string{"h264"}, copyAudio: []string{"aac"}},
	{format: "wmv", label: "WMV", muxer: "asf", video: wmv2, audio: wmav2, copyVideo: []string{"wmv2"}, copyAudio: []string{"wmav2"}},
	{format: "flv", label: "FLV", muxer: "flv", video: h264, audio: aac, copyVideo: []string{"h264"}, copyAudio: []string{"aac"}},
	{format: "ogv", label: "OGV", muxer: "ogv", video: theora, audio: vorbis, copyVideo: []string{"theora"}, copyAudio: []string{"vorbis"}},
	{format: "3gp", label: "3GP", muxer: "3gp", video: h264, audio: aac, copyVideo: []string{"h264"}, copyAudio: []string{"aac"}},
	{format: "3g2", label: "3G2", muxer: "3g2", video: h264, audio: aac, copyVideo: []string{"h264"}, copyAudio: []string{"aac"}},
	{format: "mpeg", label: "MPEG", muxer: "mpeg", video: mpeg2, audio: mp2, copyVideo: []string{"mpeg2video"}, copyAudio: []string{"mp2"}},
	{format: "mpg", label: "MPG", muxer: "mpeg", video: mpeg2, audio: mp2, copyVideo: []string{"mpeg2video"}, copyAudio: []string{"mp2"}},
	{format: "ts", label: "TS", muxer: "mpegts", video: h264, audio: aac, copyVideo: []string{"h264", "hevc", "mpeg2video"}, copyAudio: []string{"aac", "mp3", "mp2", "ac3"}},
}
