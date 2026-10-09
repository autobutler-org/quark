//go:build stress

package stress

import (
	"context"
	"net/http"
	"os"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

// TestCapacity runs each STRESS_USERS level against the server for
// STRESS_DURATION and logs a Markdown summary of it, appending it to
// STRESS_REPORT when that is set. It fails only when the harness cannot run;
// the numbers are for a reader, not a gate.
func TestCapacity(t *testing.T) {
	cfg, err := loadConfig()
	if err != nil {
		t.Fatal(err)
	}
	setup := api{base: cfg.base, http: &http.Client{Timeout: 30 * time.Second}}
	adminKey, err := setup.authKey(cfg.adminUser, cfg.adminPass)
	if err != nil {
		t.Fatalf("admin auth key: %v", err)
	}
	adminToken, err := setup.login(cfg.adminUser, adminKey)
	if err != nil {
		t.Fatalf("admin login: %v", err)
	}
	accounts, err := ensureAccounts(setup, adminToken, cfg.accounts)
	if err != nil {
		t.Fatal(err)
	}

	for _, n := range cfg.levels {
		awaitIdle(cfg.base)
		summary := runLevel(cfg, accounts, n)
		t.Log(summary)
		if cfg.report != "" {
			f, err := os.OpenFile(cfg.report, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
			if err != nil {
				t.Fatal(err)
			}
			_, err = f.WriteString(summary)
			if closeErr := f.Close(); err == nil {
				err = closeErr
			}
			if err != nil {
				t.Fatal(err)
			}
		}
		// Let the server close what this level left open before the next.
		time.Sleep(10 * time.Second)
	}
}

// runLevel starts n clients spread over a ramp, runs them for the configured
// duration, and summarizes what they saw.
func runLevel(cfg config, accounts []account, n int) string {
	ctx, cancel := context.WithTimeout(context.Background(), cfg.duration)
	defer cancel()
	rec := newRecorder()
	counts := &levelCounts{}
	var peakRSS, peakThreads atomic.Int64
	go sampleProcess(ctx, cfg.pid, &peakRSS, &peakThreads)

	// Clients arrive over the first third of the run, at most 10 s, rather
	// than in one synthetic stampede.
	ramp := min(cfg.duration/3, 10*time.Second)
	uploaders := max(1, n*cfg.uploadersPer100/100)
	if cfg.uploadersPer100 == 0 {
		uploaders = 0
	}
	started := time.Now()
	var wg sync.WaitGroup
	for i := 0; i < n; i++ {
		c := newClient(cfg, accounts[i%len(accounts)], i, rec, counts)
		delay := time.Duration(int64(ramp) * int64(i) / int64(n))
		loops := []func(context.Context){c.eventLoop, c.pollLoop}
		if i < uploaders {
			id := i
			loops = append(loops, func(ctx context.Context) { c.uploadLoop(ctx, id) })
		}
		for _, loop := range loops {
			wg.Add(1)
			go func() {
				defer wg.Done()
				select {
				case <-ctx.Done():
					return
				case <-time.After(delay):
				}
				loop(ctx)
			}()
		}
		wg.Add(1)
		go func() {
			defer wg.Done()
			<-ctx.Done()
			c.bg.Wait()
			c.http.CloseIdleConnections()
		}()
	}
	<-ctx.Done()
	elapsed := time.Since(started)
	waiting := counts.waiting.Load()
	wg.Wait()
	return summarize(n, elapsed, rec, counts, waiting, peakRSS.Load(), peakThreads.Load())
}
