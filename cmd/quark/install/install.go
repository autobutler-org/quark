package install

import (
	"fmt"

	"github.com/autobutler-org/quark/internal/install"

	"github.com/spf13/cobra"
)

func Cmd() *cobra.Command {
	var systemOnly bool
	cmd := &cobra.Command{
		Use:   "install",
		Short: "Install Quark's system service",
		Long:  `The install command sets up Quark as a system service, allowing it to run in the background and start automatically on system boot.`,
		RunE: func(cmd *cobra.Command, args []string) error {
			if systemOnly {
				if err := install.Install(true); err != nil {
					return fmt.Errorf("failed to reapply Quark's system setup; run `sudo quark install` to repair it: %w", err)
				}
				fmt.Println("Quark's system setup is up to date.")
				return nil
			}
			fmt.Println("Install Quark's system service")
			if err := install.Install(false); err != nil {
				return fmt.Errorf("failed to install Quark as a system service; %w", err)
			}
			fmt.Println("Quark's system service was installed successfully.")
			return nil
		},
	}
	cmd.Flags().BoolVar(&systemOnly, "system-only", false,
		"reapply the system setup (service account, sudoers rule, systemd unit) without copying the binary "+
			"or restarting the service; the systemd unit runs this as root before every start")

	return cmd
}
