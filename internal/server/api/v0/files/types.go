package v0_files

import (
	"time"

	"github.com/autobutler-org/quark/pkg/util/serverutil"
)

type router struct{}

func (r *router) Routes() []*serverutil.Route {
	return []*serverutil.Route{
		convertXlsxRoute,
		deleteFilesRoute,
		downloadArchiveFileRoute,
		downloadFileRoute,
		extractFileRoute,
		listArchiveRoute,
		listFilesByTypeRoute,
		listFilesRoute,
		listRecentFilesRoute,
		moveFileRoute,
		newFolderRoute,
		searchFilesRoute,
		searchContentRoute,
		statFileRoute,
		uploadFilesRoute,
		uploadFilesNestedRoute,
		createUploadSessionRoute,
		uploadSessionChunkRoute,
		getUploadSessionRoute,
		deleteUploadSessionRoute,
	}
}

type createUploadSessionRequest struct {
	RootDir   string `json:"rootDir"`
	FileName  string `json:"fileName"`
	TotalSize int64  `json:"totalSize"`
	Serial    string `json:"serial"`
	Overwrite bool   `json:"overwrite"`
	KeepBoth  bool   `json:"keepBoth"`
}

type createUploadSessionResponse struct {
	SessionID string    `json:"sessionId"`
	Offset    int64     `json:"offset"`
	ExpiresAt time.Time `json:"expiresAt"`
}

type uploadSessionStatusResponse struct {
	SessionID string    `json:"sessionId"`
	Offset    int64     `json:"offset"`
	TotalSize int64     `json:"totalSize"`
	FileName  string    `json:"fileName"`
	RootDir   string    `json:"rootDir"`
	ExpiresAt time.Time `json:"expiresAt"`
}

type moveFileRequest struct {
	OldFilePath     string `json:"oldFilePath"`
	NewFilePath     string `json:"newFilePath"`
	OldDeviceSerial string `json:"oldDeviceSerial"`
	NewDeviceSerial string `json:"newDeviceSerial"`
}

type uploadChunkResponse struct {
	SessionID string `json:"sessionId"`
	Offset    int64  `json:"offset"`
	Complete  bool   `json:"complete"`
	Path      string `json:"path,omitempty"`
}
