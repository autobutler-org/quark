package aptutil

// resolvedParams is ConfigureParams with every default filled in.
type resolvedParams struct {
	root     string
	runner   Runner
	lookPath func(string) (string, error)
}
