//go:build chaos

package chaos

import (
	"encoding/json"
	"net/http"
	"sync"
	"testing"
)

// Login bursts trip the per-IP login rate limit, so they must run after every
// other case that logs in. Go runs tests in file order, then declaration
// order, and this file's name sorts last; keep it that way.

// TestLoginBurstInvalidCredentials lightly bursts login with invalid
// credentials. 401 and 429 are both success for resilience; 5xx must stay low.
// Kept smaller than the status burst to avoid a long lockout on a shared host.
func TestLoginBurstInvalidCredentials(t *testing.T) {
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

	hist.assertBurst(t, "login burst")
}

// TestMixedPublicBurst mixes status GETs with malformed login POSTs. 401/429
// on the login half are expected and acceptable.
func TestMixedPublicBurst(t *testing.T) {
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

	hist.assertBurst(t, "mixed public burst")
}
