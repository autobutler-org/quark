package trimutil

// cspell:words aevalsrc copyts demuxer demuxers geq keyint lavfi libopus libx264 nokey noprint signalstats silencedetect YAVG

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"testing"
	"time"

	"github.com/autobutler-org/quark/pkg/util/jobutil"
	"github.com/autobutler-org/quark/pkg/util/videoutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// The playback tests (#3418) read trim and remux output the way a player
// does, with ffmpeg's demuxers and decoders, rather than the way sprocket
// writes it. Each fixture is generated at test time so that every frame and
// the one beep in the audio say where on the source's timeline they came
// from: frame n is a flat gray of luma 16+2n, and the audio is silent but for
// a beep at fixtureBeep. A clip is then checked for the frame it shows first,
// where its beep lands, and how long it lasts. ffmpeg is one player among
// several; docs/testing/video-trim-playback-checklist.md covers the rest.

const (
	fixtureFPS      = 24
	fixtureDuration = 4 * time.Second
	fixtureBeep     = 2500 * time.Millisecond
	// aacFrame is one AAC frame at 48 kHz, sprocket's bound on A/V offset.
	aacFrame = time.Second * 1024 / 48000
)

// requireFFmpeg skips the test when ffmpeg or ffprobe is not installed.
func requireFFmpeg(t *testing.T) {
	t.Helper()
	for _, tool := range []string{"ffmpeg", "ffprobe"} {
		if _, err := exec.LookPath(tool); err != nil {
			t.Skipf("%s is not installed", tool)
		}
	}
}

// runTool runs ffmpeg or ffprobe and returns what it printed, stderr after
// stdout, failing the test if it fails.
func runTool(t *testing.T, name string, args ...string) string {
	t.Helper()
	var out bytes.Buffer
	cmd := exec.Command(name, args...)
	cmd.Stdout = &out
	cmd.Stderr = &out
	if err := cmd.Run(); err != nil {
		t.Fatalf("%s %v: %v\n%s", name, args, err, out.String())
	}
	return out.String()
}

// makeFixture writes fixtureDuration of H.264 with a keyframe every second
// and audio in audioCodec to dir/name, its container taken from the name.
func makeFixture(t *testing.T, dir, name, audioCodec string) string {
	t.Helper()
	p := filepath.Join(dir, name)
	seconds := strconv.FormatFloat(fixtureDuration.Seconds(), 'f', -1, 64)
	beep := fixtureBeep.Seconds()
	runTool(t, "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
		"-f", "lavfi", "-i", "color=c=black:s=64x64:r="+strconv.Itoa(fixtureFPS)+":d="+seconds+
			",format=yuv420p,geq=lum='16+2*N':cb=128:cr=128",
		"-f", "lavfi", "-i", "aevalsrc='if(between(t,"+strconv.FormatFloat(beep, 'f', -1, 64)+","+
			strconv.FormatFloat(beep+0.1, 'f', -1, 64)+"),0.5*sin(2*PI*1000*t),0)':s=48000:d="+seconds,
		"-c:v", "libx264", "-qp", "0", "-pix_fmt", "yuv420p",
		"-g", strconv.Itoa(fixtureFPS), "-keyint_min", strconv.Itoa(fixtureFPS), "-sc_threshold", "0",
		"-c:a", audioCodec, "-b:a", "128k", p)
	return p
}

// playback is what ffmpeg makes of a clip.
type playback struct {
	// shownFrom is where on the source's timeline the clip's first frame is
	// shown from: its source time less its time in the clip.
	shownFrom time.Duration
	// heardFrom is the same for the audio, from where the beep lands.
	heardFrom time.Duration
	// duration is the container's duration.
	duration time.Duration
}

var (
	ptsTimeRE    = regexp.MustCompile(`pts_time:(-?[0-9.]+)`)
	yavgRE       = regexp.MustCompile(`lavfi\.signalstats\.YAVG=([0-9.]+)`)
	silenceEndRE = regexp.MustCompile(`silence_end: (-?[0-9.]+)`)
	numbersRE    = regexp.MustCompile(`-?[0-9]+(\.[0-9]+)?`)
)

// seconds is s, a decimal number of seconds ffmpeg printed, as a Duration.
func seconds(t *testing.T, s string) time.Duration {
	t.Helper()
	f, err := strconv.ParseFloat(s, 64)
	if err != nil {
		t.Fatal(err)
	}
	return time.Duration(math.Round(f * float64(time.Second)))
}

// play reads the clip at p with ffmpeg as a player would. -copyts keeps the
// timestamps the demuxer reports, edit lists applied, instead of moving the
// first to zero. A player's clock starts at zero, or at the first timestamp
// where that is later (a TS clip keeps its source's), and it drops anything
// before: MKV's lead-in sits at negative timestamps.
func play(t *testing.T, p string) playback {
	t.Helper()
	var pb playback
	probe := runTool(t, "ffprobe", "-v", "error", "-show_entries", "format=start_time,duration",
		"-of", "default=noprint_wrappers=1:nokey=1", p)
	fields := numbersRE.FindAllString(probe, -1)
	if len(fields) != 2 {
		t.Fatalf("ffprobe found no start and duration in %s:\n%s", p, probe)
	}
	zero := max(0, seconds(t, fields[0]))
	pb.duration = seconds(t, fields[1])

	video := runTool(t, "ffmpeg", "-hide_banner", "-copyts", "-i", p, "-an",
		"-vf", fmt.Sprintf("select=gte(t\\,%f),signalstats,metadata=print:key=lavfi.signalstats.YAVG", zero.Seconds()),
		"-frames:v", "1", "-f", "null", "-")
	pts, yavg := ptsTimeRE.FindStringSubmatch(video), yavgRE.FindStringSubmatch(video)
	if pts == nil || yavg == nil {
		t.Fatalf("no first frame in %s:\n%s", p, video)
	}
	luma, err := strconv.ParseFloat(yavg[1], 64)
	if err != nil {
		t.Fatal(err)
	}
	frame := int(math.Round((luma - 16) / 2))
	pb.shownFrom = time.Second*time.Duration(frame)/fixtureFPS - (seconds(t, pts[1]) - zero)

	audio := runTool(t, "ffmpeg", "-hide_banner", "-copyts", "-i", p, "-vn",
		"-af", "silencedetect=n=-30dB:d=0.05", "-f", "null", "-")
	end := silenceEndRE.FindStringSubmatch(audio)
	if end == nil {
		t.Fatalf("no beep in %s:\n%s", p, audio)
	}
	pb.heardFrom = fixtureBeep - (seconds(t, end[1]) - zero)
	return pb
}

// checkPlayback checks a clip ffmpeg played as pb shows the source from
// wantStart, within a millisecond, keeps its audio within one AAC frame of
// its video, and lasts until end, within a frame.
func checkPlayback(t *testing.T, pb playback, wantStart, end time.Duration) {
	t.Helper()
	t.Logf("shown from %v, heard from %v, lasts %v", pb.shownFrom, pb.heardFrom, pb.duration)
	if d := pb.shownFrom - wantStart; d < -time.Millisecond || d > time.Millisecond {
		t.Errorf("first frame is the source at %v, want %v", pb.shownFrom, wantStart)
	}
	if d := pb.heardFrom - pb.shownFrom; d < -aacFrame || d > aacFrame {
		t.Errorf("audio is %v off the video, more than one AAC frame (%v); flag it, do not re-encode (#2378)", d, aacFrame)
	}
	// ffprobe prints microseconds, so a frame's worth can read a hair over.
	frame := time.Second/fixtureFPS + time.Millisecond
	if d := pb.duration - (end - wantStart); d < -frame || d > frame {
		t.Errorf("clip lasts %v, want %v from %v to %v, give or take a frame", pb.duration, end-wantStart, wantStart, end)
	}
}

// extract copies path out of fsys into dir, for ffmpeg to read.
func extract(t *testing.T, fsys vfs.VFS, path, dir string) string {
	t.Helper()
	src, err := fsys.Open(context.Background(), path)
	if err != nil {
		t.Fatal(err)
	}
	defer src.Close()
	p := filepath.Join(dir, filepath.Base(path))
	dst, err := os.Create(p)
	if err != nil {
		t.Fatal(err)
	}
	defer dst.Close()
	if _, err := io.Copy(dst, src); err != nil {
		t.Fatal(err)
	}
	return p
}

// TestTrimJobClipsPlayFromTheirReportedStart runs trim jobs between two
// keyframes, where sprocket keeps the frames back to the keyframe but hides
// them, and plays each clip: it must show the source from the start the job
// reported, which is the requested one, with its audio in sync. MP4 hides the
// lead-in behind an edit list and MKV behind CodecDelay.
func TestTrimJobClipsPlayFromTheirReportedStart(t *testing.T) {
	requireFFmpeg(t)
	const start, end = 1500 * time.Millisecond, 3500 * time.Millisecond
	cases := []struct{ name, file, audio string }{
		{"mp4 with aac", "gen.mp4", "aac"},
		{"mkv with opus", "gen.mkv", "libopus"},
		{"mkv with aac", "gen-aac.mkv", "aac"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			dir := t.TempDir()
			h := newHarness(t, nil)
			f, err := os.Open(makeFixture(t, dir, c.file, c.audio))
			if err != nil {
				t.Fatal(err)
			}
			defer f.Close()
			if err := h.fsys.Write(context.Background(), c.file, f, vfs.WriteOptions{}); err != nil {
				t.Fatal(err)
			}

			job := h.run(t, h.enqueue(t, Params{RelPath: c.file, Serial: testSerial, StartMs: start.Milliseconds(), EndMs: end.Milliseconds()}).ID)
			if job.Status != jobutil.StatusCompleted {
				t.Fatalf("job = %s (%s), want completed", job.Status, job.Error)
			}
			var result Result
			if err := json.Unmarshal(job.Detail, &result); err != nil {
				t.Fatal(err)
			}
			if result.ActualStartMs != start.Milliseconds() {
				t.Errorf("actualStartMs = %d, want the requested %d", result.ActualStartMs, start.Milliseconds())
			}
			checkPlayback(t, play(t, extract(t, h.fsys, result.RelPath, dir)), time.Duration(result.ActualStartMs)*time.Millisecond, end)
		})
	}
}

// TestTrimIntoTSPlaysItsLeadIn trims into TS, which has nothing to hide the
// lead-in behind: the clip shows the source from the keyframe before the
// start, and that keyframe is the start Trim reports, so a label built from
// actualStartMs is still right. TrimFile never writes TS, since a TS source
// cannot be cut, but Trim takes the format from the source's name.
func TestTrimIntoTSPlaysItsLeadIn(t *testing.T) {
	requireFFmpeg(t)
	const start, end = 1500 * time.Millisecond, 3500 * time.Millisecond
	dir := t.TempDir()
	src, err := os.Open(makeFixture(t, dir, "gen.mp4", "aac"))
	if err != nil {
		t.Fatal(err)
	}
	defer src.Close()
	info, err := src.Stat()
	if err != nil {
		t.Fatal(err)
	}
	clip := filepath.Join(dir, "clip.ts")
	out, err := os.Create(clip)
	if err != nil {
		t.Fatal(err)
	}
	defer out.Close()
	result, err := videoutil.Trim(context.Background(), videoutil.TrimParams{
		Source: videoutil.Source{File: src, Size: info.Size(), Name: "gen.ts"},
		Output: out, Start: start, End: end,
	})
	if err != nil {
		t.Fatal(err)
	}
	if keyframe := time.Second; result.Start != keyframe {
		t.Fatalf("Start = %v, want the keyframe %v before %v", result.Start, keyframe, start)
	}
	checkPlayback(t, play(t, clip), result.Start, end)
}

// TestRemuxMKVToMP4PlaysInSync remuxes Matroska into MP4, which sprocket
// writes fragmented, and plays the whole result: it must start on the first
// frame, keep its audio in sync, and last as long as the source.
func TestRemuxMKVToMP4PlaysInSync(t *testing.T) {
	requireFFmpeg(t)
	dir := t.TempDir()
	src, err := os.Open(makeFixture(t, dir, "gen.mkv", "aac"))
	if err != nil {
		t.Fatal(err)
	}
	defer src.Close()
	info, err := src.Stat()
	if err != nil {
		t.Fatal(err)
	}
	remuxed := filepath.Join(dir, "remuxed.mp4")
	out, err := os.Create(remuxed)
	if err != nil {
		t.Fatal(err)
	}
	defer out.Close()
	if err := videoutil.Remux(context.Background(), videoutil.RemuxParams{
		Source: videoutil.Source{File: src, Size: info.Size(), Name: "gen.mkv"},
		Output: out, Format: "mp4",
	}); err != nil {
		t.Fatal(err)
	}
	checkPlayback(t, play(t, remuxed), 0, fixtureDuration)
}
