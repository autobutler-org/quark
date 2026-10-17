package musicutil_test

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/binary"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

func cat(parts ...[]byte) []byte { return bytes.Join(parts, nil) }

func be32(n uint32) []byte { return binary.BigEndian.AppendUint32(nil, n) }

func le32(n uint32) []byte { return binary.LittleEndian.AppendUint32(nil, n) }

// flacBlock is one FLAC metadata block; the caller marks the last.
func flacBlock(typ byte, last bool, body []byte) []byte {
	if last {
		typ |= 0x80
	}
	return cat([]byte{typ, byte(len(body) >> 16), byte(len(body) >> 8), byte(len(body))}, body)
}

// flacFile is a FLAC file of the given length in seconds at 44.1 kHz, with
// Vorbis comments such as "TITLE=x", and an embedded front cover when
// picture is not nil.
func flacFile(seconds uint64, picture []byte, comments ...string) []byte {
	const rate = 44100
	info := make([]byte, 34)
	binary.BigEndian.PutUint64(info[10:18], uint64(rate)<<44|uint64(1)<<41|uint64(15)<<36|seconds*rate)
	vc := cat(le32(4), []byte("test"), le32(uint32(len(comments))))
	for _, c := range comments {
		vc = cat(vc, le32(uint32(len(c))), []byte(c))
	}
	out := cat([]byte("fLaC"), flacBlock(0, false, info), flacBlock(4, picture == nil, vc))
	if picture != nil {
		mime := "image/jpeg"
		block := cat(be32(3), be32(uint32(len(mime))), []byte(mime), be32(0), make([]byte, 16), be32(uint32(len(picture))), picture)
		out = cat(out, flacBlock(6, true, block))
	}
	return append(out, make([]byte, 64)...)
}

// tagged is a FLAC file carrying the common tags.
func tagged(title, artist, album, genre string, track int) []byte {
	return flacFile(180, nil,
		"TITLE="+title, "ARTIST="+artist, "ALBUM="+album, "GENRE="+genre,
		"TRACKNUMBER="+string(rune('0'+track)), "DATE=1999")
}

// countingVFS counts the files opened through it.
type countingVFS struct {
	vfs.VFS
	opened []string
}

func (c *countingVFS) Open(ctx context.Context, path string) (vfs.File, error) {
	c.opened = append(c.opened, path)
	return c.VFS.Open(ctx, path)
}

// memFS is an in-memory namespace holding files.
func memFS(t *testing.T, files map[string][]byte) *countingVFS {
	t.Helper()
	fsys := &countingVFS{VFS: vfs.NewMemVFS(vfs.FilesNamespace(""))}
	for p, data := range files {
		write(t, fsys, p, data)
	}
	return fsys
}

func write(t *testing.T, fsys vfs.VFS, p string, data []byte) {
	t.Helper()
	ctx := context.Background()
	if dir := filepath.Dir(p); dir != "." {
		if err := fsys.MkdirAll(ctx, dir); err != nil {
			t.Fatal(err)
		}
	}
	if err := fsys.Write(ctx, p, bytes.NewReader(data), vfs.WriteOptions{}); err != nil {
		t.Fatal(err)
	}
}

// rows is every stored row, keyed by path.
func rows(t *testing.T, sqlDB *sql.DB) map[string]db.MusicTrack {
	t.Helper()
	all, err := db.NewQueries(sqlDB).ListMusicTracksAfter(context.Background(), db.ListMusicTracksAfterParams{Limit: 1 << 20})
	if err != nil {
		t.Fatal(err)
	}
	out := map[string]db.MusicTrack{}
	for _, row := range all {
		out[row.Serial+":"+row.RelPath] = row
	}
	return out
}

// adminAccess is an admin's access, which filters nothing.
func adminAccess(t *testing.T) accessutil.Access {
	t.Helper()
	loaded, err := accessutil.Load(accessutil.LoadParams{Principal: accessutil.System})
	if err != nil {
		t.Fatal(err)
	}
	return loaded.Access
}

// usbDetector presents one USB drive with a serial, rooted at a temp dir.
type usbDetector struct {
	mountPoint string
	serial     string
}

func (d usbDetector) DetectDevices() ([]storageutil.Device, error) {
	return []storageutil.Device{{Name: "USB", MountPoint: d.mountPoint, UsbInfo: serialOnly{serial: d.serial}}}, nil
}

// serialOnly implements only GetSerial; any other call panics.
type serialOnly struct {
	storageutil.UsbDevice
	serial string
}

func (u serialOnly) GetSerial() string { return u.serial }

const usbSerial = "USB-MUSIC"

// memberAccess is a non-admin granted read on each of paths on the USB drive
// usbSerial. The drive's files directory exists, so access checks resolve.
func memberAccess(t *testing.T, database *db.DatabaseSqlc, paths ...string) accessutil.Access {
	t.Helper()
	ctx := context.Background()
	mountPoint := t.TempDir()
	if err := os.MkdirAll(filepath.Join(mountPoint, "quark", "data", "files"), 0o755); err != nil {
		t.Fatal(err)
	}
	user, err := database.Queries.CreateUser(ctx, db.CreateUserParams{
		Username: "bob" + strings.ReplaceAll(strings.Join(paths, "_"), "/", "-"), PasswordHash: "h", RecoveryPhraseHash: "r",
	})
	if err != nil {
		t.Fatal(err)
	}
	for _, p := range paths {
		if err := database.Queries.SetUserPathAccess(ctx, db.SetUserPathAccessParams{
			DeviceSerial: usbSerial,
			RelPath:      p,
			UserID:       sql.NullInt64{Int64: user.ID, Valid: true},
			Level:        accessutil.Read.String(),
		}); err != nil {
			t.Fatal(err)
		}
	}
	loaded, err := accessutil.Load(accessutil.LoadParams{
		Ctx: ctx, Database: database, Principal: accessutil.Principal{UserID: user.ID},
		Storage: storageutil.NewStorageService(usbDetector{mountPoint: mountPoint, serial: usbSerial}),
	})
	if err != nil {
		t.Fatal(err)
	}
	return loaded.Access
}

// newDB is an empty SQLite database with the schema applied.
func newDB(t *testing.T) *db.DatabaseSqlc {
	t.Helper()
	t.Setenv("HOME", t.TempDir())
	return dbtest.NewDB(t)
}
