package main

import (
	"bufio"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"strings"
)

// ledger records the operations Quark acknowledged, one line each, flushed
// before the next operation starts. It lives outside the LazyFS mount, so the
// cut that loses data not yet flushed on the mount cannot lose a line of it.
type ledger struct {
	f *os.File
}

// withLedger opens the ledger at path for the duration of fn.
func withLedger(path string, fn func(*ledger) error) error {
	f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		return err
	}
	runErr := fn(&ledger{f: f})
	return errors.Join(runErr, f.Close())
}

// ack appends one acknowledged operation.
func (l *ledger) ack(fields ...string) error {
	if _, err := fmt.Fprintln(l.f, strings.Join(fields, " ")); err != nil {
		return err
	}
	return l.f.Sync()
}

// readLedger returns the ledger's lines split into fields. A ledger that was
// never written means nothing was acknowledged.
func readLedger(path string) ([][]string, error) {
	f, err := os.Open(path)
	if errors.Is(err, fs.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	defer func() { _ = f.Close() }()

	var lines [][]string
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		if fields := strings.Fields(scanner.Text()); len(fields) > 0 {
			lines = append(lines, fields)
		}
	}
	return lines, scanner.Err()
}
