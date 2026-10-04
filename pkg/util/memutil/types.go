package memutil

// resolvedDropInParams is InstallDropInParams with every default filled in.
type resolvedDropInParams struct {
	root     string
	run      Runner
	totalRAM func() (uint64, error)
}
