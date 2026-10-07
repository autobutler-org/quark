package ratelimitutil

// MaxGuardRecords exposes the failure table's bound to the external tests.
const MaxGuardRecords = maxGuardRecords

// Records reports how many failure records the guard holds, so the external
// tests can see the table shrink when forgotten records are swept.
func (g *LoginGuard) Records() int {
	g.mu.Lock()
	defer g.mu.Unlock()
	return len(g.records)
}
