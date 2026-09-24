package storageutil

import (
	"archive/zip"
	"context"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"log"
	"mime/multipart"
	"os"
	"path/filepath"
	"time"

	"github.com/autobutler-org/quark/pkg/util/derivativeutil"
	"github.com/autobutler-org/quark/pkg/util/iosemutil"
)

// BackupToDeviceParams contains parameters for backing up a device
type BackupToDeviceParams struct {
	SourceDeviceSerial string               `json:"sourceDeviceSerial"`
	TargetDeviceSerial string               `json:"targetDeviceSerial"`
	IOSemaphore        *iosemutil.Semaphore `json:"-"` // not JSON-serialized; set by handler to throttle file copies
}

// BackupToDeviceResult contains the data of a backup operation
type BackupToDeviceResult struct {
	SourceDeviceSerial string
	TargetDeviceSerial string
}

// BackupToDeviceChannel is a channel for backing up devices
type BackupToDeviceChannel chan BackupToDeviceParams

func (s *StorageService) BackupToDevice(params BackupToDeviceParams) (*BackupToDeviceResult, error) {
	// NOTE: Empty string returns the first internal storage
	sourceDevice, err := s.FindManagedDeviceBySerial(params.SourceDeviceSerial)
	if err != nil {
		return nil, err // coverage: ignore - requires device detection failure
	}

	targetDevice, err := s.FindManagedDeviceBySerial(params.TargetDeviceSerial)
	if err != nil {
		return nil, err // coverage: ignore - requires device detection failure
	}

	return BackupToDeviceWithDevices(params, sourceDevice, targetDevice)
}

// BackupToDeviceWithDevices performs a device backup using pre-resolved source and target devices.
// Use this in tests to inject test devices without hitting the real filesystem detector.
func BackupToDeviceWithDevices(params BackupToDeviceParams, sourceDevice *ManagedDevice, targetDevice *ManagedDevice) (*BackupToDeviceResult, error) {
	if sourceDevice == nil {
		return nil, errors.New("source device not found")
	}
	if targetDevice == nil {
		return nil, errors.New("target device not found")
	}

	if params.SourceDeviceSerial == params.TargetDeviceSerial {
		return nil, errors.New("source and target devices cannot be the same")
	}

	sourceDirFs := os.DirFS(sourceDevice.FilesDir)
	// Walk all contents of sourceDirFs. If the file exists in targetDevice.FilesDir, it will be overwritten. If it doesn't exist, it will be created.
	err := fs.WalkDir(sourceDirFs, ".", func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		sourcePath := filepath.Join(sourceDevice.FilesDir, path)
		targetPath := filepath.Join(targetDevice.FilesDir, path)

		// Backup directory
		if d.IsDir() {
			return os.MkdirAll(targetPath, 0755)
		}

		// Acquire IO semaphore before copying to yield to interactive requests.
		if params.IOSemaphore != nil {
			if !params.IOSemaphore.AcquireDefault(context.Background()) {
				return fmt.Errorf("backup: IO semaphore timeout copying %s", path)
			}
			defer params.IOSemaphore.Release()
		}

		// Backup file
		// For files, copy the content from source to target
		srcFile, err := os.Open(sourcePath)
		if err != nil {
			return fmt.Errorf("failed to open source file: %w", err)
		}
		defer srcFile.Close()

		destDir := filepath.Dir(targetPath)
		if err := os.MkdirAll(destDir, 0755); err != nil {
			return fmt.Errorf("failed to create target directory: %w", err)
		}

		// Truncate the file if it already exists, or create it if it doesn't exist
		destFile, err := os.Create(targetPath)
		if err != nil {
			return fmt.Errorf("failed to create target file: %w", err)
		}
		defer destFile.Close()

		if _, err := io.Copy(destFile, srcFile); err != nil {
			return fmt.Errorf("failed to copy file content: %w", err)
		}
		return nil
	})

	if err != nil {
		return nil, fmt.Errorf("backup failed: %w", err)
	}

	// Placeholder implementation - in a real implementation, this would perform the backup logic
	return &BackupToDeviceResult{
		SourceDeviceSerial: params.SourceDeviceSerial,
		TargetDeviceSerial: params.TargetDeviceSerial,
	}, nil
}

// DeleteFilesParams contains parameters for deleting files
type DeleteFilesParams struct {
	RootDir      string
	FilePaths    []string
	DeviceSerial string
}

// DeleteFilesResult contains the result of a delete operation
type DeleteFilesResult struct {
	RootDir string
}

// DeleteFilesChannel is a channel for deleting files
type DeleteFilesChannel chan DeleteFilesParams

// DeleteFiles removes files from the filesystem, handling both single and multi-device scenarios
func (s *StorageService) DeleteFiles(params DeleteFilesParams) (*DeleteFilesResult, error) {
	device, err := s.FindManagedDeviceBySerial(params.DeviceSerial)
	if err != nil {
		return nil, err // coverage: ignore - requires device detection failure
	}

	defaultFilesDir, err := GetFilesDir()
	if err != nil {
		return nil, fmt.Errorf("failed to get files directory: %w", err)
	}

	return DeleteFilesImpl(params, device, defaultFilesDir)
}

// DeleteFilesImpl removes files using pre-resolved device and files directory.
// Use this in tests to inject test devices without hitting the real filesystem detector.
func DeleteFilesImpl(params DeleteFilesParams, device *ManagedDevice, defaultFilesDir string) (*DeleteFilesResult, error) {
	filesDir := defaultFilesDir
	if device != nil {
		filesDir = device.FilesDir
	}
	for _, filePath := range params.FilePaths {
		fullPath, err := safeJoin(filesDir, params.RootDir, filePath)
		if err != nil {
			return nil, fmt.Errorf("invalid file path: %w", err)
		}
		if err := os.RemoveAll(fullPath); err != nil { // coverage: ignore - requires filesystem permission errors
			return nil, fmt.Errorf("failed to delete %s: %w", filePath, err)
		}
	}

	return &DeleteFilesResult{
		RootDir: params.RootDir,
	}, nil
}

// MoveFileParams contains parameters for moving a file
type MoveFileParams struct {
	OldFilePath     string
	NewFilePath     string
	OldDeviceSerial string
	NewDeviceSerial string
}

// MoveFileResult contains the result of a move operation
type MoveFileResult struct {
	NewDir string
}

// MoveFileChannel is a channel for moving files
type MoveFileChannel chan MoveFileParams

// MoveFile moves a file from one location to another
func (s *StorageService) MoveFile(params MoveFileParams) (*MoveFileResult, error) {
	oldDevice, err := s.FindManagedDeviceBySerial(params.OldDeviceSerial)
	if err != nil {
		return nil, err // coverage: ignore - requires device detection failure
	}
	newDevice, err := s.FindManagedDeviceBySerial(params.NewDeviceSerial)
	if err != nil {
		return nil, err // coverage: ignore - requires device detection failure
	}

	defaultFilesDir, err := GetFilesDir()
	if err != nil {
		return nil, fmt.Errorf("failed to get files directory: %w", err)
	}

	return MoveFileImpl(params, oldDevice, newDevice, defaultFilesDir)
}

// MoveFileImpl moves a file using pre-resolved devices and files directory.
// Use this in tests to inject test devices without hitting the real filesystem detector.
func MoveFileImpl(params MoveFileParams, oldDevice *ManagedDevice, newDevice *ManagedDevice, defaultFilesDir string) (*MoveFileResult, error) {
	oldFilesDir := defaultFilesDir
	if oldDevice != nil {
		oldFilesDir = oldDevice.FilesDir
	}
	newFilesDir := defaultFilesDir
	if newDevice != nil {
		newFilesDir = newDevice.FilesDir
	}

	oldFullPath, err := safeJoin(oldFilesDir, params.OldFilePath)
	if err != nil {
		return nil, fmt.Errorf("invalid old file path: %w", err)
	}
	newFullPath, err := safeJoin(newFilesDir, params.NewFilePath)
	if err != nil {
		return nil, fmt.Errorf("invalid new file path: %w", err)
	}

	newFullDir := filepath.Dir(newFullPath)
	if err := os.MkdirAll(newFullDir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create directory: %w", err) // coverage: ignore - requires filesystem permission errors
	}

	if err := os.Rename(oldFullPath, newFullPath); err != nil { // coverage: ignore - requires filesystem permission errors or cross-device move
		// Check for cross-device link error (EXDEV)
		if linkErr, ok := err.(*os.LinkError); ok && linkErr.Err.Error() == "invalid cross-device link" {
			// Fallback: copy then delete
			srcFile, err := os.Open(oldFullPath)
			if err != nil {
				return nil, fmt.Errorf("failed to open source file for cross-device move: %w", err)
			}
			defer srcFile.Close()

			// Create destination file
			dstFile, err := os.Create(newFullPath)
			if err != nil {
				return nil, fmt.Errorf("failed to create destination file for cross-device move: %w", err)
			}
			defer dstFile.Close()

			if _, err := io.Copy(dstFile, srcFile); err != nil {
				return nil, fmt.Errorf("failed to copy file for cross-device move: %w", err)
			}

			// Remove the source file
			if err := os.Remove(oldFullPath); err != nil {
				return nil, fmt.Errorf("failed to remove source file after cross-device move: %w", err)
			}
		} else {
			return nil, fmt.Errorf("failed to move file: %w", err)
		}
	}

	// The file has moved; a derivative left behind only costs a thumbnail.
	if err := derivativeutil.Move(oldFullPath, newFullPath); err != nil {
		log.Printf("quark: move %q: carry derivatives: %v", params.OldFilePath, err)
	}

	newDir := filepath.Dir(params.NewFilePath)
	if newDir == "." {
		newDir = ""
	}

	return &MoveFileResult{
		NewDir: newDir,
	}, nil
}

// CreateFolderParams contains parameters for creating a folder
type CreateFolderParams struct {
	FolderDir    string
	FolderName   string
	DeviceSerial string
}

// CreateFolderResult contains the result of a folder creation operation
type CreateFolderResult struct {
	CurrentDir string
}

// CreateFolderChannel is a channel for creating folders
type CreateFolderChannel chan CreateFolderParams

// CreateFolder creates a new folder in the filesystem
func (s *StorageService) CreateFolder(params CreateFolderParams) (*CreateFolderResult, error) {
	device, err := s.FindManagedDeviceBySerial(params.DeviceSerial)
	if err != nil {
		return nil, err // coverage: ignore - requires device detection failure
	}
	defaultFilesDir, err := GetFilesDir()
	if err != nil {
		return nil, fmt.Errorf("failed to get files directory: %w", err)
	}
	return CreateFolderImpl(params, device, defaultFilesDir)
}

// CreateFolderImpl creates a folder using a pre-resolved device and files directory.
// Use this in tests to inject test devices without hitting the real filesystem detector.
func CreateFolderImpl(params CreateFolderParams, device *ManagedDevice, defaultFilesDir string) (*CreateFolderResult, error) {
	rootDir := defaultFilesDir
	if device != nil {
		rootDir = device.FilesDir
	}
	fullPath, err := safeJoin(rootDir, params.FolderDir, params.FolderName)
	if err != nil {
		return nil, fmt.Errorf("invalid folder path: %w", err)
	}

	if err := os.MkdirAll(fullPath, 0755); err != nil {
		return nil, fmt.Errorf("failed to create folder: %w", err) // coverage: ignore - requires filesystem permission errors
	}

	return &CreateFolderResult{
		CurrentDir: params.FolderDir,
	}, nil
}

// DownloadFileParams contains parameters for downloading a file
type DownloadFileParams struct {
	FilePath     string
	DeviceSerial string
}

// DownloadFileResult contains the result of a download operation
type DownloadFileResult struct {
	FullPath  string
	FileType  FileType
	IsFolder  bool
	ZipWriter *zip.Writer
	MimeType  string
}

// DownloadFile prepares a file for download, handling both files and folders (as zip)
func (s *StorageService) DownloadFile(params DownloadFileParams) (*DownloadFileResult, error) {
	device, err := s.FindManagedDeviceBySerial(params.DeviceSerial)
	if err != nil {
		return nil, err // coverage: ignore - requires device detection failure
	}
	defaultFilesDir, err := GetFilesDir()
	if err != nil {
		return nil, fmt.Errorf("failed to get files directory: %w", err)
	}
	return DownloadFileImpl(params, device, defaultFilesDir)
}

// DownloadFileImpl prepares a file for download using pre-resolved device and files directory.
// Use this in tests to inject test devices without hitting the real filesystem detector.
func DownloadFileImpl(params DownloadFileParams, device *ManagedDevice, defaultFilesDir string) (*DownloadFileResult, error) {
	filesDir := defaultFilesDir
	if device != nil {
		filesDir = device.FilesDir
	}
	fullPath, err := safeJoin(filesDir, params.FilePath)
	if err != nil {
		return nil, fmt.Errorf("invalid file path: %w", err)
	}
	fileType := DetermineFileTypeFromPath(fullPath)

	if _, err := os.Stat(fullPath); os.IsNotExist(err) {
		return nil, fmt.Errorf("file not found: %s", params.FilePath)
	}

	return &DownloadFileResult{
		FullPath: fullPath,
		FileType: fileType,
		IsFolder: fileType == FileTypeFolder,
	}, nil
}

// UploadFilesStreamedParams contains parameters for streaming file uploads
type UploadFilesStreamedParams struct {
	Reader       *multipart.Reader
	RootDir      string
	DeviceSerial string
	// Overwrite, when true, replaces an existing file with the same name.
	Overwrite bool
	// KeepBoth, when true, lands a file whose name is taken under the first
	// free [NumberedName] instead (file_(1).qdoc). With neither set, a taken
	// name fails with an error wrapping [fs.ErrExist] and nothing is written:
	// the caller chooses, the server never renames on its own (#2016).
	KeepBoth bool
	// Sidecar, when set, is handed every part that is not a file.
	Sidecar SidecarFunc
}

// UploadedFile is one file an upload wrote.
type UploadedFile struct {
	// Path is where the file landed, files-relative, after any file_(1) rename.
	Path string
	// Created is false when the upload replaced a file that was already there.
	Created bool
	// SourceName is the file name the client sent, before any rename. A
	// sidecar part names its file by it.
	SourceName string
}

// SidecarFunc receives a part of a multipart upload that is not a file, with
// the files written so far, while the part can still be read. A client
// sends a file's thumbnail and preview this way (#2379), right after the file.
type SidecarFunc func(part *multipart.Part, written []UploadedFile)

// UploadFilesStreamedResult lists the files an upload wrote, in the order they
// arrived. When the upload fails partway it still lists the files that landed
// before the failure.
type UploadFilesStreamedResult struct {
	Written []UploadedFile
}

// UploadFilesStreamed streams multipart file uploads directly to disk
func (s *StorageService) UploadFilesStreamed(params UploadFilesStreamedParams) (UploadFilesStreamedResult, error) {
	device, err := s.FindManagedDeviceBySerial(params.DeviceSerial)
	if err != nil {
		return UploadFilesStreamedResult{}, fmt.Errorf("device not found: %w", err)
	}
	defaultFilesDir, err := GetFilesDir()
	if err != nil {
		return UploadFilesStreamedResult{}, fmt.Errorf("failed to get files directory: %w", err)
	}
	return UploadFilesStreamedImpl(params, device, defaultFilesDir)
}

// UploadFilesStreamedImpl streams file uploads using pre-resolved device and files directory.
// Use this in tests to inject test devices without hitting the real filesystem detector.
func UploadFilesStreamedImpl(params UploadFilesStreamedParams, device *ManagedDevice, defaultFilesDir string) (UploadFilesStreamedResult, error) {
	var result UploadFilesStreamedResult
	filesDir := defaultFilesDir
	if device != nil {
		filesDir = device.FilesDir
	}

	for {
		part, err := params.Reader.NextPart()
		if err == io.EOF {
			break
		}
		if err != nil {
			return result, err
		}

		formName := part.FormName()
		if formName == "files" && part.FileName() != "" {
			// Strip any directory components from the client-supplied filename to
			// prevent path traversal via the filename itself.
			fileName := filepath.Base(part.FileName())
			destDir, err := safeJoin(filesDir, params.RootDir)
			if err != nil {
				part.Close()
				return result, fmt.Errorf("invalid upload directory: %w", err)
			}
			if err := os.MkdirAll(destDir, 0755); err != nil {
				part.Close()
				return result, fmt.Errorf("failed to create directory: %w", err)
			}
			destPath, err := safeJoin(destDir, fileName)
			if err != nil {
				part.Close()
				return result, fmt.Errorf("invalid file name: %w", err)
			}

			// Overwriting a file that is already there creates nothing new, so the
			// caller keeps whatever access rows it had (#1903).
			_, statErr := os.Stat(destPath)
			existed := params.Overwrite && statErr == nil

			// Refused before a byte of the part is read, so a clash costs a
			// round trip rather than the upload. The link below re-checks, for a
			// file that appears while this one streams in.
			if statErr == nil && !params.Overwrite && !params.KeepBoth {
				part.Close()
				return result, nameTaken(params.RootDir, fileName)
			}

			// Write to a temp file in data/tmp, then atomically move into place.
			// Determine tmp base adjacent to the data dir so it's on the
			// same filesystem as the final destination.
			dataDir := GetDataDir()
			if device != nil {
				// device.FilesDir is <dataDir>/files, so parent is device data dir
				dataDir = filepath.Dir(filesDir)
			}
			tmpBase := filepath.Join(dataDir, "tmp")
			if err := os.MkdirAll(tmpBase, 0755); err != nil {
				part.Close()
				return result, fmt.Errorf("failed to create tmp directory: %w", err)
			}

			// Create a temp file and write the uploaded content to it
			tmpFile, err := os.CreateTemp(tmpBase, "upload-*")
			if err != nil {
				part.Close()
				return result, fmt.Errorf("failed to create temp file: %w", err)
			}
			tmpPath := tmpFile.Name()
			if _, err := io.Copy(tmpFile, part); err != nil {
				tmpFile.Close()
				os.Remove(tmpPath)
				part.Close()
				return result, fmt.Errorf("failed to write temp file: %w", err)
			}
			tmpFile.Close()

			// Place the temp file at destPath.
			// Overwrite: replace atomically (os.Rename) or truncate on copy.
			// KeepBoth: retry with numbered names on conflict.
			// Neither: a conflict is the caller's to resolve.
			candidate := fileName
			i := 0
			for {
				var joinErr error
				destPath, joinErr = safeJoin(destDir, candidate)
				if joinErr != nil {
					os.Remove(tmpPath)
					part.Close()
					return result, fmt.Errorf("invalid candidate path: %w", joinErr)
				}

				if params.Overwrite {
					// Atomic replace: rename temp over existing file (works same-FS).
					if err := os.Rename(tmpPath, destPath); err == nil {
						break
					}
					// Cross-device: fall back to truncating copy.
					tmpR, rerr := os.Open(tmpPath)
					if rerr != nil {
						os.Remove(tmpPath)
						part.Close()
						return result, fmt.Errorf("failed to open temp file for fallback copy: %w", rerr)
					}
					dst, derr := os.OpenFile(destPath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0644)
					if derr != nil {
						tmpR.Close()
						os.Remove(tmpPath)
						part.Close()
						return result, fmt.Errorf("failed to open destination for overwrite: %w", derr)
					}
					if _, cerr := io.Copy(dst, tmpR); cerr != nil {
						dst.Close()
						tmpR.Close()
						os.Remove(tmpPath)
						part.Close()
						return result, fmt.Errorf("failed to copy temp to destination: %w", cerr)
					}
					dst.Close()
					tmpR.Close()
					os.Remove(tmpPath)
					break
				}

				// Attempt hard link first (atomic and avoids extra copy)
				linkErr := os.Link(tmpPath, destPath)
				if linkErr == nil {
					// Success: remove temp and we're done
					os.Remove(tmpPath)
					break
				}
				if os.IsExist(linkErr) {
					if !params.KeepBoth {
						os.Remove(tmpPath)
						part.Close()
						return result, nameTaken(params.RootDir, fileName)
					}
					i++
					candidate = NumberedName(fileName, i)
					continue
				}
				// Hard link failed for another reason (e.g., EXDEV). Try exclusive create + copy.
				// Open temp for reading
				tmpR, rerr := os.Open(tmpPath)
				if rerr != nil {
					os.Remove(tmpPath)
					part.Close()
					return result, fmt.Errorf("failed to open temp file for fallback copy: %w", rerr)
				}
				dst, derr := os.OpenFile(destPath, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0644)
				if derr == nil {
					// Copy content from temp to destination
					if _, cerr := io.Copy(dst, tmpR); cerr != nil {
						dst.Close()
						tmpR.Close()
						os.Remove(tmpPath)
						part.Close()
						return result, fmt.Errorf("failed to copy temp to destination: %w", cerr)
					}
					dst.Close()
					tmpR.Close()
					os.Remove(tmpPath)
					break
				}
				tmpR.Close()
				if os.IsExist(derr) {
					if !params.KeepBoth {
						os.Remove(tmpPath)
						part.Close()
						return result, nameTaken(params.RootDir, fileName)
					}
					i++
					candidate = NumberedName(fileName, i)
					continue
				}
				// Unknown error creating destination
				os.Remove(tmpPath)
				part.Close()
				return result, fmt.Errorf("failed to move uploaded file into place: linkErr=%v createErr=%v", linkErr, derr)
			}
			part.Close()
			rel, relErr := filepath.Rel(filepath.Clean(filesDir), destPath)
			if relErr != nil {
				return result, fmt.Errorf("failed to locate the uploaded file: %w", relErr)
			}
			result.Written = append(result.Written, UploadedFile{Path: filepath.ToSlash(rel), Created: !existed, SourceName: fileName})
		} else {
			if params.Sidecar != nil {
				params.Sidecar(part, result.Written)
			}
			part.Close()
		}
	}
	return result, nil
}

// ResolvePathParams names a file by the path a request uses for it.
type ResolvePathParams struct {
	// RelPath is files-relative; a TrashPath resolves into the trash.
	RelPath string
	// Serial names the device, empty for the internal one.
	Serial string
}

// ResolvePathResult is where the file sits on disk.
type ResolvePathResult struct {
	FullPath string
}

// ResolvePath turns a files-relative path into the OS path it names on its
// device, refusing one that climbs out of the files directory or the trash.
// It does not check that anything is there.
func (s *StorageService) ResolvePath(params ResolvePathParams) (ResolvePathResult, error) {
	filesDir, err := s.trashFilesDir(params.Serial)
	if err != nil {
		return ResolvePathResult{}, err
	}
	var full string
	if IsTrashPath(params.RelPath) {
		full, err = JoinTrashPath(filesDir, params.RelPath)
	} else {
		full, err = safeJoin(filesDir, params.RelPath)
	}
	if err != nil {
		return ResolvePathResult{}, err
	}
	return ResolvePathResult{FullPath: full}, nil
}

// CopyDerivativesParams names a file and the copy just made of it.
type CopyDerivativesParams struct {
	Serial      string
	FromRelPath string
	ToRelPath   string
}

// CopyDerivatives gives a copy made outside CopyFile — through the VFS — the
// client-rendered thumbnails and previews of its original, as CopyFile does.
func (s *StorageService) CopyDerivatives(params CopyDerivativesParams) error {
	from, err := s.ResolvePath(ResolvePathParams{RelPath: params.FromRelPath, Serial: params.Serial})
	if err != nil {
		return err
	}
	to, err := s.ResolvePath(ResolvePathParams{RelPath: params.ToRelPath, Serial: params.Serial})
	if err != nil {
		return err
	}
	return derivativeutil.Copy(from.FullPath, to.FullPath)
}

// StatFileParams contains parameters for stat-ing a file or directory
type StatFileParams struct {
	FilePath     string
	DeviceSerial string
}

// StatFileResult contains the result of a stat operation
type StatFileResult struct {
	FullPath string
	IsDir    bool
	FileType FileType
	Name     string
	Size     int64
	ModTime  time.Time
}

// StatFile resolves a files-relative path to its filesystem metadata.
func (s *StorageService) StatFile(params StatFileParams) (*StatFileResult, error) {
	device, err := s.FindManagedDeviceBySerial(params.DeviceSerial)
	if err != nil {
		return nil, err // coverage: ignore - requires device detection failure
	}
	defaultFilesDir, err := GetFilesDir()
	if err != nil {
		return nil, fmt.Errorf("failed to get files directory: %w", err)
	}
	return StatFileImpl(params, device, defaultFilesDir)
}

// StatFileImpl resolves a path using pre-resolved device and files directory.
// Use this in tests to inject test devices without hitting the real filesystem detector.
func StatFileImpl(params StatFileParams, device *ManagedDevice, defaultFilesDir string) (*StatFileResult, error) {
	filesDir := defaultFilesDir
	if device != nil {
		filesDir = device.FilesDir
	}
	fullPath, err := safeJoin(filesDir, params.FilePath)
	if err != nil {
		return nil, fmt.Errorf("invalid file path: %w", err)
	}
	info, err := os.Stat(fullPath)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, fmt.Errorf("path not found: %s", params.FilePath)
		}
		return nil, fmt.Errorf("failed to stat path: %w", err)
	}
	isDir := info.IsDir()
	var fileType FileType
	if isDir {
		fileType = FileTypeFolder
	} else {
		fileType = DetermineFileTypeFromPath(fullPath)
	}
	return &StatFileResult{
		FullPath: fullPath,
		IsDir:    isDir,
		FileType: fileType,
		Name:     info.Name(),
		Size:     info.Size(),
		ModTime:  info.ModTime(),
	}, nil
}

// CopyFileParams contains parameters for duplicating a file in-place.
type CopyFileParams struct {
	// RelPath is the files-relative path of the source file.
	RelPath      string
	DeviceSerial string
}

// CopyFileResult contains the result of a file copy operation.
type CopyFileResult struct {
	// NewRelPath is the files-relative path of the newly created copy.
	NewRelPath string
}

// CopyFile duplicates a file within the same files directory, producing a
// non-conflicting name by appending "_copy" (and further numeric suffixes if
// needed). It is the service-layer entry point and resolves the device by
// serial before delegating to CopyFileImpl.
func (s *StorageService) CopyFile(params CopyFileParams) (*CopyFileResult, error) {
	device, err := s.FindManagedDeviceBySerial(params.DeviceSerial)
	if err != nil {
		return nil, err // coverage: ignore - requires device detection failure
	}
	defaultFilesDir, err := GetFilesDir()
	if err != nil {
		return nil, fmt.Errorf("failed to get files directory: %w", err)
	}
	return CopyFileImpl(params, device, defaultFilesDir)
}

// CopyFileImpl duplicates a file using pre-resolved device and files directory.
// Use this in tests to inject test devices without hitting the real filesystem
// detector.
func CopyFileImpl(params CopyFileParams, device *ManagedDevice, defaultFilesDir string) (*CopyFileResult, error) {
	filesDir := defaultFilesDir
	if device != nil {
		filesDir = device.FilesDir
	}

	srcFull, err := safeJoin(filesDir, params.RelPath)
	if err != nil {
		return nil, fmt.Errorf("invalid relPath: %w", err)
	}

	if _, err := os.Stat(srcFull); os.IsNotExist(err) {
		return nil, fmt.Errorf("%w: %s", ErrPathNotFound, params.RelPath)
	} else if err != nil {
		return nil, fmt.Errorf("failed to stat source: %w", err)
	}

	ext := filepath.Ext(srcFull)
	stem := srcFull[:len(srcFull)-len(ext)]
	destFull := GetNonConflictingPath(stem + "_copy" + ext)

	if err := copyFileContents(srcFull, destFull); err != nil {
		return nil, fmt.Errorf("copy failed: %w", err)
	}
	if err := derivativeutil.Copy(srcFull, destFull); err != nil {
		log.Printf("quark: copy %q: copy derivatives: %v", params.RelPath, err)
	}

	newRelPath, err := filepath.Rel(filesDir, destFull)
	if err != nil {
		return nil, fmt.Errorf("failed to compute relative path: %w", err)
	}

	return &CopyFileResult{NewRelPath: newRelPath}, nil
}

// copyFileContents writes the contents of src to dst.
func copyFileContents(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()

	out, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer func() {
		if cerr := out.Close(); cerr != nil && err == nil {
			err = cerr
		}
	}()

	_, err = io.Copy(out, in)
	return err
}
