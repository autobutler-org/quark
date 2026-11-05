// cspell:words tsnetbridge

package main

import (
	"fmt"
	"os"
)

// main exists so `go build` of this command succeeds. The iOS and Android
// app does not run it: hook/build.dart builds the C library instead, and
// that build ignores main.
func main() {
	fmt.Fprintln(os.Stderr, "tsnetbridge is a C library. The iOS and Android app builds it with hook/build.dart.")
	os.Exit(2)
}
