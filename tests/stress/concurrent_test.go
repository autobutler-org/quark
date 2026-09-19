//go:build stress

package stress

import (
	"encoding/json"
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

	total := hist.total()
	five := hist.count5xx()
	t.Logf("auth/status burst: workers=%d bursts=%d total=%d hist=[%s]", workers, perWorker, total, hist.summary())
	if total == 0 {
		t.Fatal("no responses collected")
	}
	if float64(five)/float64(total) > max5xxFraction {
		t.Fatalf("5xx storm: %d/%d (%.0f%%) exceeded %.0f%% threshold", five, total, 100*float64(five)/float64(total), 100*max5xxFraction)
	}
}

// TestZZLoginBurstInvalidCredentials lightly bursts login with invalid
// credentials. Named ZZ* so it runs after authenticated cases: a 429 from this
// burst must not poison earlier ensureSession calls (session is also warmed in
// TestMain). 401 and 429 are both success for resilience; 5xx must stay low.
// Kept smaller than status burst to avoid prolonged IP lockout on shared labs.
func TestZZLoginBurstInvalidCredentials(t *testing.T) {
	c := newClient(t)
	c.requireBackend(t)

	workers := min(concurrency(), 8)
	perWorker := min(bursts(), 4)
	payload, _ := json.Marshal(map[string]string{
		"username": "stress-nonexistent",
		"password": "stress-wrong-password",
	})

	hist := newStatusHist()
	var wg sync.WaitGroup
	wg.Add(workers)
	for i := 0; i < workers; i++ {
		go func() {
			defer wg.Done()
			for j := 0; j < perWorker; j++ {
				hist.add(c.exchange(http.MethodPost, "/api/v0/auth/login", payload, map[string]string{
					"Content-Type": "application/json",
				}))
			}
		}()
	}
	wg.Wait()

	total := hist.total()
	five := hist.count5xx()
	t.Logf("login burst: workers=%d bursts=%d total=%d hist=[%s]", workers, perWorker, total, hist.summary())
	if total == 0 {
		t.Fatal("no responses collected")
	}
	if float64(five)/float64(total) > max5xxFraction {
		t.Fatalf("5xx storm on login burst: %d/%d", five, total)
	}
}

// TestZZMixedPublicBurst mixes status GETs with malformed login POSTs.
// Runs late (ZZ*) so login rate-limit pressure does not precede authed cases.
// 401/429 on the login half are expected and acceptable.
func TestZZMixedPublicBurst(t *testing.T) {
	c := newClient(t)
	c.requireBackend(t)

	workers := concurrency()
	perWorker := bursts()
	hist := newStatusHist()
	var wg sync.WaitGroup
	wg.Add(workers)
	for i := 0; i < workers; i++ {
		id := i
		go func() {
			defer wg.Done()
			for j := 0; j < perWorker; j++ {
				if (id+j)%2 == 0 {
					hist.add(c.exchange(http.MethodGet, "/api/v0/auth/status", nil, nil))
				} else {
					hist.add(c.exchange(http.MethodPost, "/api/v0/auth/login", []byte(`{}`), map[string]string{
						"Content-Type": "application/json",
					}))
				}
			}
		}()
	}
	wg.Wait()

	total := hist.total()
	five := hist.count5xx()
	t.Logf("mixed public burst: total=%d hist=[%s]", total, hist.summary())
	if total == 0 {
		t.Fatal("no responses collected")
	}
	if float64(five)/float64(total) > max5xxFraction {
		t.Fatalf("5xx storm on mixed burst: %d/%d", five, total)
	}
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

	total := hist.total()
	five := hist.count5xx()
	t.Logf("authed reads: total=%d hist=[%s]", total, hist.summary())
	if total == 0 {
		t.Fatal("no responses collected")
	}
	if float64(five)/float64(total) > max5xxFraction {
		t.Fatalf("5xx storm on authed reads: %d/%d", five, total)
	}
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
