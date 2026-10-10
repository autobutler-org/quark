// Package resetutil tells a running instance that the install it booted on has
// been factory reset, possibly by another instance serving the same database.
package resetutil

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"time"

	"github.com/autobutler-org/quark/internal/db"
)

// DefaultWatchInterval is how often Watch reads the install id, and so the
// longest an instance keeps serving after a reset it did not perform.
//
// ponytail: a poll, one indexed single-row read per interval. Push the reset
// over the instance relay (#2965) instead once there is one.
const DefaultWatchInterval = 2 * time.Second

// WatchParams configures Watch.
type WatchParams struct {
	Queries *db.Queries
	// Interval is the time between reads; zero means DefaultWatchInterval.
	Interval time.Duration
	// OnReset is called once, from Watch's goroutine, when the install id is
	// no longer the one this instance booted on. Everything the process holds
	// in memory then belongs to an install that no longer exists (the vault
	// key, the access and listing caches, the file index, the cached "setup
	// is done"), so the server's OnReset restarts the process.
	OnReset func()
}

// WatchResult is what Watch read before it returned.
type WatchResult struct {
	// InstallID is the install this instance booted on.
	InstallID string
}

// Watch reads the install id, then keeps reading it in the background until
// ctx is done, and calls OnReset when it changes. db.ResetDatabase issues a
// new id in the transaction that resets the database and
// authutil.DeleteAccount rotates it for a reset that leaves the database
// standing, so a change means a factory reset ran, on this instance or on
// another one (#3085).
//
// A read that fails is retried at the next tick: a database that cannot be
// asked has not said the install is gone.
func Watch(ctx context.Context, params WatchParams) (WatchResult, error) {
	if params.Queries == nil || params.OnReset == nil {
		return WatchResult{}, errors.New("queries and OnReset are required")
	}
	interval := params.Interval
	if interval <= 0 {
		interval = DefaultWatchInterval
	}
	booted, err := params.Queries.GetInstallID(ctx)
	if err != nil {
		return WatchResult{}, fmt.Errorf("failed to read the install id: %w", err)
	}

	go func() {
		ticker := time.NewTicker(interval)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
			}
			current, err := params.Queries.GetInstallID(ctx)
			if err != nil {
				slog.Debug("resetutil: failed to read the install id", "err", err)
				continue
			}
			if current != booted {
				params.OnReset()
				return
			}
		}
	}()
	return WatchResult{InstallID: booted}, nil
}
