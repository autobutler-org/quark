// Package workerutil runs the background worker that processes backup-to-device requests off a channel and reports
// their errors.
package workerutil

import (
	"log"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

type Worker interface {
	Process() error
	GetQuitChannel() chan struct{}
	GetErrorChannel() chan error
	LogErrors() error
	GetBackupToDeviceChannel() storageutil.BackupToDeviceChannel
}

func NewWorker(svc *storageutil.StorageService) Worker {
	return &worker{
		quitChannel:           make(chan struct{}),
		errorChannel:          make(chan error),
		backupToDeviceChannel: make(storageutil.BackupToDeviceChannel),
		storageService:        svc,
	}
}

func (w *worker) Process() error {
	for {
		select {
		case backupReq := <-w.backupToDeviceChannel:
			if _, err := w.storageService.BackupToDevice(backupReq); err != nil {
				w.errorChannel <- err
			}
		case <-w.quitChannel:
			return nil
		}
	}
}

func (w *worker) GetQuitChannel() chan struct{} {
	return w.quitChannel
}

func (w *worker) GetErrorChannel() chan error {
	return w.errorChannel
}

func (w *worker) LogErrors() error {
	for {
		err := <-w.errorChannel
		if err != nil {
			log.Printf("Worker service error: %v\n", err)
		}
	}
}

func (w *worker) GetBackupToDeviceChannel() storageutil.BackupToDeviceChannel {
	return w.backupToDeviceChannel
}
