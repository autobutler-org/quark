// Package install is the quark install subcommand, which sets Quark up as a system service through
// internal/install, caps its memory through pkg/util/memutil and keeps the OS patched through pkg/util/aptutil.
package install

import (
	"fmt"
	"os"
	"runtime"
	"strings"

	"github.com/autobutler-org/quark/internal/install"
	"github.com/autobutler-org/quark/pkg/util/aptutil"
	"github.com/autobutler-org/quark/pkg/util/memutil"

	"github.com/spf13/cobra"
)

func Cmd() *cobra.Command {
	var systemOnly, releaseKernelHold bool
	cmd := &cobra.Command{
		Use:   "install",
		Short: "Install Quark's system service",
		Long:  `The install command sets up Quark as a system service, allowing it to run in the background and start automatically on system boot.`,
		RunE: func(cmd *cobra.Command, args []string) error {
			if releaseKernelHold {
				result, err := aptutil.ReleaseHold(aptutil.ConfigureParams{})
				if err != nil {
					return fmt.Errorf("failed to release the kernel hold: %w", err)
				}
				fmt.Printf("Released the hold on %d package(s): %s\n", len(result.Released), strings.Join(result.Released, " "))
				fmt.Printf("Delete %s to hold them again on the next start.\n", aptutil.HoldReleasedMarkerPath)
				return nil
			}
			// Before the unit is (re)started, so a first install starts
			// under the ceiling.
			configureMemoryCeiling()
			if systemOnly {
				if err := install.Install(true); err != nil {
					return fmt.Errorf("failed to reapply Quark's system setup; run `sudo quark install` to repair it: %w", err)
				}
				configureApt()
				fmt.Println("Quark's system setup is up to date.")
				return nil
			}
			fmt.Println("Install Quark's system service")
			if err := install.Install(false); err != nil {
				return fmt.Errorf("failed to install Quark as a system service; %w", err)
			}
			configureApt()
			fmt.Println("Quark's system service was installed successfully.")
			return nil
		},
	}
	cmd.Flags().BoolVar(&systemOnly, "system-only", false,
		"reapply the system setup (service account, sudoers rule, systemd unit, security updates, kernel hold) "+
			"without copying the binary or restarting the service; the systemd unit runs this as root before every start")
	cmd.Flags().BoolVar(&releaseKernelHold, "release-kernel-hold", false,
		"lift the hold on the kernel, bootloader and board packages and keep it lifted until "+
			aptutil.HoldReleasedMarkerPath+" is deleted")

	return cmd
}

// configureMemoryCeiling writes the systemd drop-in that caps the service's
// memory at a share of this board's RAM (#2761). A failure is reported, not
// returned, for the same reason as configureApt's.
func configureMemoryCeiling() {
	result, err := memutil.InstallDropIn(memutil.InstallDropInParams{})
	switch {
	case err != nil:
		fmt.Fprintf(os.Stderr, "warning: the service's memory ceiling is not set up: %v\n", err)
	case result.Skipped:
		fmt.Printf("Skipping the memory ceiling: %s.\n", result.SkipReason)
	case result.Changed:
		fmt.Printf("Capped the service at MemoryHigh=%d MiB, MemoryMax=%d MiB.\n",
			result.Limits.MemoryHigh>>20, result.Limits.MemoryMax>>20)
	}
}

// configureApt turns on Debian security updates and holds the kernel and
// board packages (#2122, #2124). A failure is reported, not returned: the
// service setup before it succeeded, and the next start tries again.
func configureApt() {
	if runtime.GOOS != "linux" {
		return
	}
	result, err := aptutil.Configure(aptutil.ConfigureParams{})
	switch {
	case result.Skipped:
		fmt.Printf("Skipping security updates and the kernel hold: %s.\n", result.SkipReason)
	case result.HoldReleased:
		fmt.Printf("The kernel hold is released; delete %s to restore it.\n", aptutil.HoldReleasedMarkerPath)
	case len(result.Held) > 0:
		fmt.Printf("Held %s.\n", strings.Join(result.Held, " "))
	}
	if result.InstallQueued {
		fmt.Println("Installing unattended-upgrades in the background.")
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "warning: security updates and the kernel hold are not fully set up: %v\n", err)
	}
}
