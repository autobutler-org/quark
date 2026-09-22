// Command lsusb prints the USB devices Quark can see, with their partitions and mount points; -storage narrows the
// list to storage devices. It is a debugging aid, not part of the shipped server.
package main

import (
	"flag"
	"fmt"
	"os"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

func main() {
	onlyStorage := flag.Bool("storage", false, "List only storage devices")
	flag.Parse()

	devices, err := storageutil.ListUsbDevices(*onlyStorage)
	if err != nil {
		fmt.Println("Error:", err)
		os.Exit(1)
	}
	for _, dev := range devices {
		fmt.Printf("%+v\n", dev)
		if mountPath := dev.GetMountPath(); mountPath != "" {
			fmt.Printf("  Mounted at: %s", mountPath)
			partitions, err := dev.Partitions()
			if err != nil {
				fmt.Printf("  Error retrieving partitions: %v", err)
			} else {
				for _, partition := range partitions {
					if pMountPath, err := partition.MountPath(); err == nil {
						sizeBytes, err := partition.SizeBytes()
						if err != nil {
							fmt.Printf("  Error retrieving partition size: %v", err)
							continue
						}
						fmt.Printf("  Partition(%s) mounted at: %s with size(bytes): %d", partition, pMountPath, sizeBytes)
					}
				}
			}

		} else if dev.IsStorageDevice() {
			partitions, err := dev.Partitions()
			if err != nil {
				fmt.Printf("  Error retrieving partitions: %v", err)
			} else {
				for _, partition := range partitions {
					mountCommand := partition.MountCommand("/mnt/usb")
					fmt.Printf(
						"  Partition(%s) not mounted, mount with: %s",
						partition,
						mountCommand,
					)
				}
			}
		}
		fmt.Println()
	}
}
