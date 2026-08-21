Z# Security Policy

Quark stores people's photos, documents, and passwords on hardware in their homes. We take reports seriously.

## Supported Versions

Only the latest release is supported. Devices auto-update from the release feed, and fixes ship in the next tag rather
than as backports — there are no maintained release branches.

Check your version in **Settings → About**, or run `quark version`. The current release is listed on the
[releases page](https://github.com/autobutler-org/quark/releases).

## Reporting a Vulnerability

**Do not open a public issue.** File a private security advisory:

<https://github.com/autobutler-org/quark/security/advisories/new>

Please include:

- What you found, and which component it affects
- Steps to reproduce
- The version you tested
- What an attacker could actually do with it, and what access they'd need first

We'll acknowledge the report, tell you whether we consider it a vulnerability, and let you know when a fix is out. If
you'd like credit in the advisory, say so and tell us how you want to be named.

Please give us a chance to ship a fix before publishing. Devices auto-update, but not instantly.

## In scope

- Authentication and session handling — login, setup, recovery phrases, token lifetime
- Vault cryptography and anything that could expose stored credentials
- Path traversal or unauthorized file access through the API
- Anything reachable from outside the home network, including remote access and the update mechanism
- Privilege escalation on the device, especially around USB mounting
- The release pipeline, the OS images, and dependency supply chain
- Anything that sends user data off the device

That last one matters most. Quark's entire premise is that your data stays in your house. If you find something that
contradicts that — a request to a third party, telemetry, a file leaving the device — report it as a vulnerability even
if nothing is technically "exploitable."

## Out of scope

- Attacks requiring physical access to an unlocked device. The threat model assumes the box is in your home; if someone
  is standing over it, they have already won.
- The wide-open state before first-boot setup completes. This is documented and intentional — see
  [docs/auth.md](docs/auth.md).
- Scanner output with no demonstrated impact
- Missing hardening headers or best-practice deviations with no path to exploitation
- Denial of service against your own device by your own request

If you're unsure whether something is in scope, file the advisory anyway and let us decide.

## Non-critical concerns

Hardening ideas, defense-in-depth improvements, and non-exploitable concerns can go in the public tracker using the
[security issue template](https://github.com/autobutler-org/quark/issues/new?template=security.yaml).
