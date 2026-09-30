package featureflagutil

// registry declares every beta flag. Adding a beta is one entry here plus its
// gate checks. Retiring one is deleting its entry and gates, and appending a
// settingsutil migration that drops its key.
var registry = []Flag{
	{
		Key:   Chat,
		Label: "Chat",
		Description: "Encrypted messaging between the people on this Quark. Turning it off hides chat " +
			"from everyone; stored messages and keys are kept, not deleted. It is not a security measure.",
		Default:      true,
		IntroducedIn: "#2414",
		SunsetIssue:  2577,
	},
	{
		Key:   Calendar,
		Label: "Calendar",
		Description: "The household calendar everyone on this Quark shares. Turning it off hides the " +
			"calendar from everyone; stored events are kept, not deleted. It is not a security measure.",
		Default:      true,
		IntroducedIn: "#1144",
		SunsetIssue:  2610,
	},
}
