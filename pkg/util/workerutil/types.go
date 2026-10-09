package workerutil

type worker struct {
	quitChannel  chan struct{}
	errorChannel chan error
}
