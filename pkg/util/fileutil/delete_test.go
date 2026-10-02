package fileutil_test

import (
	"context"
	"errors"
	"fmt"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/fileutil"
)

// --- ValidateDeleteFiles ---

func TestValidateDeleteFilesRefusesBadPaths(t *testing.T) {
	cases := []struct {
		name    string
		rootDir string
		paths   []string
	}{
		{"parent", "", []string{".."}},
		{"climbs out", "", []string{"../../etc/passwd"}},
		{"climbs out of rootDir", "photos", []string{"../../etc/passwd"}},
		{"rootDir climbs out", "../..", []string{"etc/passwd"}},
		{"absolute rootDir climbs out", "/photos", []string{"../../etc/passwd"}},
		{"files directory itself", "", []string{"."}},
		{"empty", "", []string{""}},
		{"one bad path among good ones", "", []string{"a.txt", "../b.txt"}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			err := fileutil.ValidateDeleteFiles(fileutil.DeleteFilesParams{RootDir: tc.rootDir, FilePaths: tc.paths})
			var invalid *fileutil.InvalidRequestError
			if !errors.As(err, &invalid) {
				t.Fatalf("ValidateDeleteFiles(%q, %q) = %v, want an InvalidRequestError", tc.rootDir, tc.paths, err)
			}
		})
	}
}

func TestValidateDeleteFilesAcceptsPathsInside(t *testing.T) {
	err := fileutil.ValidateDeleteFiles(fileutil.DeleteFilesParams{
		RootDir:   "/photos",
		FilePaths: []string{"a.jpg", "trip/b.jpg", "trip/../c.jpg"},
	})
	if err != nil {
		t.Fatalf("ValidateDeleteFiles = %v, want nil", err)
	}
}

func TestValidateDeleteFilesCapsTheBatch(t *testing.T) {
	paths := make([]string, fileutil.MaxDeleteFiles+1)
	for i := range paths {
		paths[i] = fmt.Sprintf("f%d.txt", i)
	}
	if err := fileutil.ValidateDeleteFiles(fileutil.DeleteFilesParams{FilePaths: paths[:fileutil.MaxDeleteFiles]}); err != nil {
		t.Fatalf("a batch of exactly MaxDeleteFiles = %v, want nil", err)
	}
	var invalid *fileutil.InvalidRequestError
	if err := fileutil.ValidateDeleteFiles(fileutil.DeleteFilesParams{FilePaths: paths}); !errors.As(err, &invalid) {
		t.Fatalf("a batch over MaxDeleteFiles = %v, want an InvalidRequestError", err)
	}
}

// DeleteFiles validates before it touches storage, so a bad path is refused
// as the caller's mistake rather than reaching the trash and failing there.
func TestDeleteFilesRefusesAnEscapingPath(t *testing.T) {
	_, err := fileutil.DeleteFiles(fileutil.DeleteFilesParams{FilePaths: []string{"../../etc/passwd"}})
	var invalid *fileutil.InvalidRequestError
	if !errors.As(err, &invalid) {
		t.Fatalf("DeleteFiles = %v, want an InvalidRequestError", err)
	}
}

// MoveFile and ListFiles share the check, so neither hands an escaping path
// to the storage layer to fail there with an error the handler answers 500.
func TestMoveFileRefusesAnEscapingPath(t *testing.T) {
	for _, p := range []fileutil.MoveFileParams{
		{OldFilePath: "../../etc/passwd", NewFilePath: "x"},
		{OldFilePath: "x", NewFilePath: "/a/../../x"},
	} {
		_, err := fileutil.MoveFile(p)
		var invalid *fileutil.InvalidRequestError
		if !errors.As(err, &invalid) {
			t.Errorf("MoveFile(%q -> %q) = %v, want an InvalidRequestError", p.OldFilePath, p.NewFilePath, err)
		}
	}
}

func TestListFilesRefusesAnEscapingRootDir(t *testing.T) {
	_, err := fileutil.ListFiles(fileutil.ListFilesParams{Ctx: context.Background(), RootDir: "../.."})
	var invalid *fileutil.InvalidRequestError
	if !errors.As(err, &invalid) {
		t.Fatalf("ListFiles = %v, want an InvalidRequestError", err)
	}
}
