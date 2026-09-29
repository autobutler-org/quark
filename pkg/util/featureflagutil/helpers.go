package featureflagutil

import "github.com/autobutler-org/quark/pkg/util/settingsutil"

// lookup returns the registered flag with key.
func lookup(key string) (Flag, bool) {
	for _, flag := range registry {
		if flag.Key == key {
			return flag, true
		}
	}
	return Flag{}, false
}

// enabled is the flag's stored value, or its default when none is stored.
func enabled(flag Flag) (bool, error) {
	on, set, err := settingsutil.GetFeatureFlag(flag.Key)
	if err != nil {
		return false, err
	}
	if !set {
		return flag.Default, nil
	}
	return on, nil
}
