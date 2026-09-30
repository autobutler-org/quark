// Command powercut drives Quark's real write paths on a LazyFS mount and checks
// what a simulated power cut left behind (#2517).
//
// It runs in two phases. "write" performs a stream of operations against the
// mount and appends each one to a ledger, outside the mount, only once Quark
// has reported it done: the ledger is what a client was told succeeded. run.bash
// arms LazyFS to crash partway through, which throws away everything not yet
// flushed. "check" then reads what reached the disk and holds it to the bar:
// every acknowledged operation is intact, and nothing half-written is presented
// as complete.
//
//	powercut write upload|vault <dir> <ledger>
//	powercut check upload|vault <dir> <ledger>
package main

import (
	"context"
	"fmt"
	"os"
)

func main() {
	if len(os.Args) != 5 {
		fmt.Fprintln(os.Stderr, "usage: powercut write|check upload|vault <dir> <ledger>")
		os.Exit(2)
	}
	phase, scenario, dir, ledgerPath := os.Args[1], os.Args[2], os.Args[3], os.Args[4]
	ctx := context.Background()

	var err error
	switch phase + " " + scenario {
	case "write upload":
		err = withLedger(ledgerPath, func(l *ledger) error { return writeUploads(ctx, dir, l) })
	case "write vault":
		err = withLedger(ledgerPath, func(l *ledger) error { return writeVault(ctx, dir, l) })
	case "check upload":
		err = checkUploads(dir, ledgerPath)
	case "check vault":
		err = checkVault(ctx, dir, ledgerPath)
	default:
		err = fmt.Errorf("unknown phase or scenario %q %q", phase, scenario)
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "powercut %s %s: %v\n", phase, scenario, err)
		os.Exit(1)
	}
}
