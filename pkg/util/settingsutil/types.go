package settingsutil

import "encoding/json"

// migration rewrites a settings file in place, one step of its history. It
// works on the raw JSON so it can read and remove keys Settings no longer has.
type migration func(raw map[string]json.RawMessage) error
