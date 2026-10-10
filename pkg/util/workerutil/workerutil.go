// Package workerutil runs the background worker the server starts beside it: a loop that runs until it is told to
// quit, and a logger for the errors it reports.
package workerutil

import (
	"log"
)

type Worker interface {
	Process() error
	GetQuitChannel() chan struct{}
	GetErrorChannel() chan error
	LogErrors() error
}

func NewWorker() Worker {
	return &worker{
		quitChannel:  make(chan struct{}),
		errorChannel: make(chan error),
	}
}

func (w *worker) Process() error {
	<-w.quitChannel
	return nil
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
