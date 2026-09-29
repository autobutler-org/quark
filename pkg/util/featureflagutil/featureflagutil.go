// Package featureflagutil is the registry of beta feature flags (#2542): the
// switches an admin uses to turn a feature that is still in beta on or off
// for the whole Quark. A flag is temporary. It exists only while its feature
// is in beta, and its sunset issue is where the flag, its gate checks, and
// its persisted value get deleted. Permanent configuration does not belong
// here; it lives in settingsutil.Settings.
package featureflagutil

import (
	"errors"

	"github.com/autobutler-org/quark/pkg/util/settingsutil"
)

// Chat is the key of the chat beta's flag (#2414).
const Chat = "chat"

// ErrUnknownFlag is returned for a key the registry does not declare, which
// includes every retired flag.
var ErrUnknownFlag = errors.New("unknown feature flag")

// Flag declares one beta feature's switch.
type Flag struct {
	// Key is stable: it is the flag's name in the API and in settings.json.
	Key string `json:"key"`
	// Label and Description are admin-facing copy. Description says what
	// turning the flag off actually does.
	Label       string `json:"label"`
	Description string `json:"description"`
	// Default is whether the feature is on while no admin has set the flag.
	Default bool `json:"default"`
	// IntroducedIn is the release or issue the beta started at, so a flag
	// that has outlived its beta is visible.
	IntroducedIn string `json:"introducedIn"`
	// SunsetIssue is the issue that removes the flag. Required.
	SunsetIssue int `json:"sunsetIssue"`
}

// FlagState is a registered flag joined with whether it is on now.
type FlagState struct {
	Flag
	Enabled bool `json:"enabled"`
}

// Flags returns every registered flag, in registry order.
func Flags() []Flag {
	return append([]Flag(nil), registry...)
}

// Enabled reports whether the flag key is on: the stored value, or the
// registry default when none is stored. An unknown key is off, and so is
// every flag when settings cannot be read, so a broken file does not turn a
// beta on.
func Enabled(key string) bool {
	flag, ok := lookup(key)
	if !ok {
		return false
	}
	enabled, err := enabled(flag)
	return err == nil && enabled
}

// ListFlagsParams is empty; ListFlags takes no input.
type ListFlagsParams struct{}

// ListFlagsResult is the registry joined with the current state.
type ListFlagsResult struct {
	Features []FlagState `json:"features"`
}

// ListFlags returns every registered flag with whether it is on now.
func ListFlags(ListFlagsParams) (ListFlagsResult, error) {
	features := make([]FlagState, 0, len(registry))
	for _, flag := range registry {
		on, err := enabled(flag)
		if err != nil {
			return ListFlagsResult{}, err
		}
		features = append(features, FlagState{Flag: flag, Enabled: on})
	}
	return ListFlagsResult{Features: features}, nil
}

// SetFlagParams names a flag and whether to turn it on.
type SetFlagParams struct {
	Key     string
	Enabled bool
}

// SetFlagResult is the flag after the change.
type SetFlagResult struct {
	Feature FlagState
}

// SetFlag turns a registered flag on or off and persists it. A key the
// registry does not declare is ErrUnknownFlag and writes nothing.
func SetFlag(params SetFlagParams) (SetFlagResult, error) {
	flag, ok := lookup(params.Key)
	if !ok {
		return SetFlagResult{}, ErrUnknownFlag
	}
	if err := settingsutil.SetFeatureFlag(flag.Key, params.Enabled); err != nil {
		return SetFlagResult{}, err
	}
	return SetFlagResult{Feature: FlagState{Flag: flag, Enabled: params.Enabled}}, nil
}
