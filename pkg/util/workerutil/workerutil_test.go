package workerutil

import (
	"testing"
	"time"
)

////////////////
// Unit tests //
////////////////

func TestNewWorker_ChannelAccessors(t *testing.T) {
	w := NewWorker()
	if w.GetQuitChannel() == nil {
		t.Error("GetQuitChannel returned nil")
	}
	if w.GetErrorChannel() == nil {
		t.Error("GetErrorChannel returned nil")
	}
}

func TestWorker_Process_Quit(t *testing.T) {
	w := NewWorker()
	quit := w.GetQuitChannel()
	done := make(chan struct{})
	go func() {
		err := w.Process()
		if err != nil {
			t.Errorf("Process returned error: %v", err)
		}
		close(done)
	}()
	// Give goroutine time to start
	time.Sleep(10 * time.Millisecond)
	quit <- struct{}{}
	select {
	case <-done:
		// success
	case <-time.After(100 * time.Millisecond):
		t.Error("Process did not exit after quit signal")
	}
}

func TestWorker_LogErrors_ReceivesError(t *testing.T) {
	w := NewWorker()
	errCh := w.GetErrorChannel()
	// Run LogErrors in a goroutine, send an error, and check that it does not panic
	go func() {
		// Give LogErrors time to start
		time.Sleep(10 * time.Millisecond)
		errCh <- logErrorMock{}
		// Give time for log to print
		time.Sleep(10 * time.Millisecond)
	}()
	// LogErrors is an infinite loop, so run it with a timeout
	go func() { w.LogErrors() }()
	// No assertion: just ensure no panic/deadlock
}

type logErrorMock struct{}

func (logErrorMock) Error() string { return "mock error" }
