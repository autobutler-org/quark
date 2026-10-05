package pluginutil

import "fmt"

// validatePluginID returns an error if id contains characters that could
// escape the plugins directory when used in a filepath.Join.
func validatePluginID(id string) error {
	if !pluginIDPattern.MatchString(id) {
		return fmt.Errorf("invalid plugin id %q: must match [a-zA-Z0-9_-]+", id)
	}
	return nil
}
