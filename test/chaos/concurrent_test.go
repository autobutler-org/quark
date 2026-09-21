//go:build chaos

package chaos

import (
	"net/http"
	"sync"
	"testing"
)

// TestConcurrentAuthStatusBurst hammers the public status endpoint. Expected:
// mostly 200s; 5xx fraction below max5xxFraction; transport errors logged but
// tolerated under load.
func TestConcurrentAuthStatusBurst(t *testing.T) {
	c := newClient(t)
	c.requireBackend(t)

	workers := concurrency()
	perWorker := bursts()
	hist := newStatusHist()
	var wg sync.WaitGroup
	wg.Add(workers)
	for i := 0; i < workers; i++ {
		go func() {
			defer wg.Done()
			for j := 0; j < perWorker; j++ {
				hist.add(c.exchange(http.MethodGet, "/api/v0/auth/status", nil, nil))
			}
		}()
	}
	wg.Wait()

	hist.assertBurst(t, "auth/status burst")
}

// TestConcurrentAuthenticatedReads bursts read-only authenticated endpoints
// when credentials are configured.
func TestConcurrentAuthenticatedReads(t *testing.T) {
	c := newClient(t)
	c.requireBackend(t)
	c.ensureSession(t)

	paths := []string{
		"/api/v0/files",
		"/api/v0/auth/status",
		"/api/v0/version",
		"/api/v0/health",
	}
	workers := min(concurrency(), 16)
	perWorker := min(bursts(), 4)
	hist := newStatusHist()
	var wg sync.WaitGroup
	wg.Add(workers)
	for i := 0; i < workers; i++ {
		go func(worker int) {
			defer wg.Done()
			for j := 0; j < perWorker; j++ {
				path := paths[(worker+j)%len(paths)]
				hist.add(c.exchange(http.MethodGet, path, nil, nil))
			}
		}(i)
	}
	wg.Wait()

	hist.assertBurst(t, "authed reads")
}
