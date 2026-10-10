package videoutil

import (
	"context"
	"errors"
	"io"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/autobutler-org/quark/pkg/vfs"
)

// memWith returns a MemVFS holding the host file src at p.
func memWith(t *testing.T, src, p string) *vfs.MemVFS {
	t.Helper()
	fsys := vfs.NewMemVFS("files")
	put(t, fsys, p, openFixture(t, src).File)
	return fsys
}

func put(t *testing.T, fsys vfs.VFS, p string, r io.Reader) {
	t.Helper()
	if err := fsys.Write(context.Background(), p, r, vfs.WriteOptions{}); err != nil {
		t.Fatal(err)
	}
}

// names lists the files in dir.
func names(t *testing.T, fsys vfs.VFS, dir string) []string {
	t.Helper()
	list, err := fsys.List(context.Background(), dir, nil)
	if err != nil {
		t.Fatal(err)
	}
	var out []string
	for _, fi := range list {
		out = append(out, fi.Name)
	}
	slices.Sort(out)
	return out
}

func TestTrimFileWritesTheClipBesideTheSource(t *testing.T) {
	fsys := memWith(t, gopFixture, "videos/clip.mp4")
	result, err := TrimFile(context.Background(), TrimFileParams{
		FS: fsys, Path: "videos/clip.mp4", Start: 1200 * time.Millisecond, End: 2200 * time.Millisecond,
	})
	if err != nil {
		t.Fatal(err)
	}
	if result.Path != "videos/clip_trimmed.mp4" || result.Start != 1200*time.Millisecond {
		t.Fatalf("result = %+v, want videos/clip_trimmed.mp4 shown from 1.2s", result)
	}
	clip, err := OpenSource(context.Background(), OpenSourceParams{FS: fsys, Path: result.Path})
	if err != nil {
		t.Fatal(err)
	}
	defer clip.Close()
	info, err := ProbeSource(context.Background(), clip)
	if err != nil || info.Duration < 900*time.Millisecond || info.Duration > 1100*time.Millisecond {
		t.Fatalf("clip probe = %+v, %v, want about 1s", info, err)
	}
}

// TestTrimFileKeepsEveryTakenName checks the name is found by writing, not by
// looking: the taken names stay as they were and the clip takes the next one.
func TestTrimFileKeepsEveryTakenName(t *testing.T) {
	fsys := memWith(t, gopFixture, "clip.mp4")
	put(t, fsys, "clip_trimmed.mp4", strings.NewReader("first"))
	put(t, fsys, "clip_trimmed_(1).mp4", strings.NewReader("second"))

	result, err := TrimFile(context.Background(), TrimFileParams{FS: fsys, Path: "clip.mp4", Start: 0, End: time.Second})
	if err != nil {
		t.Fatal(err)
	}
	if result.Path != "clip_trimmed_(2).mp4" {
		t.Fatalf("clip landed at %q, want clip_trimmed_(2).mp4", result.Path)
	}
	for p, want := range map[string]string{"clip_trimmed.mp4": "first", "clip_trimmed_(1).mp4": "second"} {
		f, err := fsys.Open(context.Background(), p)
		if err != nil {
			t.Fatal(err)
		}
		got, _ := io.ReadAll(f)
		_ = f.Close()
		if string(got) != want {
			t.Errorf("%s holds %q, want %q untouched", p, got, want)
		}
	}
}

// commitConflictVFS refuses the first write at commit, after reading all of
// it: another file took the name while the clip was being written.
type commitConflictVFS struct {
	*vfs.MemVFS
	refused []string
}

func (c *commitConflictVFS) Write(ctx context.Context, p string, r io.Reader, opts vfs.WriteOptions) error {
	if len(c.refused) == 0 {
		c.refused = append(c.refused, p)
		if _, err := io.Copy(io.Discard, r); err != nil {
			return err
		}
		return vfs.ErrConflict
	}
	return c.MemVFS.Write(ctx, p, r, opts)
}

func TestTrimFileTrimsAgainWhenTheNameIsTakenAtCommit(t *testing.T) {
	fsys := &commitConflictVFS{MemVFS: memWith(t, gopFixture, "clip.mp4")}
	result, err := TrimFile(context.Background(), TrimFileParams{FS: fsys, Path: "clip.mp4", Start: 0, End: time.Second})
	if err != nil {
		t.Fatal(err)
	}
	if !slices.Equal(fsys.refused, []string{"clip_trimmed.mp4"}) || result.Path != "clip_trimmed_(1).mp4" {
		t.Fatalf("refused %v, landed at %q, want clip_trimmed.mp4 refused and clip_trimmed_(1).mp4 written", fsys.refused, result.Path)
	}
	clip, err := OpenSource(context.Background(), OpenSourceParams{FS: fsys, Path: result.Path})
	if err != nil {
		t.Fatal(err)
	}
	defer clip.Close()
	if _, err := ProbeSource(context.Background(), clip); err != nil {
		t.Fatalf("the second attempt wrote no whole clip: %v", err)
	}
}

func TestTrimFileFailuresLeaveNothingBehind(t *testing.T) {
	cases := []struct {
		name, fixture, src, path string
		start                    time.Duration
		want                     error
	}{
		{"a transport stream", tsFixture, "clip.ts", "clip.ts", 0, ErrCannotTrim},
		{"a start past the end", gopFixture, "clip.mp4", "clip.mp4", 3 * time.Second, ErrStartPastEnd},
		{"a missing source", gopFixture, "clip.mp4", "gone.mp4", 0, vfs.ErrNotFound},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			fsys := memWith(t, c.fixture, c.src)
			_, err := TrimFile(context.Background(), TrimFileParams{FS: fsys, Path: c.path, Start: c.start, End: c.start + time.Second})
			if !errors.Is(err, c.want) {
				t.Fatalf("err = %v, want %v", err, c.want)
			}
			if got := names(t, fsys, ""); !slices.Equal(got, []string{c.src}) {
				t.Fatalf("namespace holds %v, want only the source", got)
			}
		})
	}
}

func TestTrimFileRefusesANonVideo(t *testing.T) {
	fsys := vfs.NewMemVFS("files")
	put(t, fsys, "notes.mp4", strings.NewReader("not a video"))
	if _, err := TrimFile(context.Background(), TrimFileParams{FS: fsys, Path: "notes.mp4", End: time.Second}); !errors.Is(err, ErrNotAVideo) {
		t.Fatalf("err = %v, want ErrNotAVideo", err)
	}
}

func TestOpenSourceRefusesAFolder(t *testing.T) {
	fsys := memWith(t, gopFixture, "videos/clip.mp4")
	if _, err := OpenSource(context.Background(), OpenSourceParams{FS: fsys, Path: "videos"}); !errors.Is(err, vfs.ErrIsDirectory) {
		t.Fatalf("err = %v, want vfs.ErrIsDirectory", err)
	}
}

func TestPlaceUnderFreeNameGivesUp(t *testing.T) {
	var tried []string
	_, err := PlaceUnderFreeName(PlaceUnderFreeNameParams{Dir: "a", Name: "clip.mp4", Place: func(p string) error {
		tried = append(tried, p)
		return vfs.ErrConflict
	}})
	if !errors.Is(err, ErrNoFreeName) || len(tried) != maxFreeNameAttempts {
		t.Fatalf("err = %v after %d tries, want ErrNoFreeName after %d", err, len(tried), maxFreeNameAttempts)
	}
	if tried[0] != "a/clip.mp4" || tried[2] != "a/clip_(2).mp4" {
		t.Fatalf("tried %v..., want a/clip.mp4 then numbered names", tried[:3])
	}
}

func TestPlaceUnderFreeNameStopsAtAnyOtherError(t *testing.T) {
	boom := errors.New("disk full")
	calls := 0
	_, err := PlaceUnderFreeName(PlaceUnderFreeNameParams{Name: "clip.mp4", Place: func(string) error {
		calls++
		return boom
	}})
	if !errors.Is(err, boom) || calls != 1 {
		t.Fatalf("err = %v after %d calls, want the error after one", err, calls)
	}
}
