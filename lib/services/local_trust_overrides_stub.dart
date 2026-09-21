// Stub for non-io platforms (web). The browser owns TLS trust, and there is no
// HttpClient to override, so this is a no-op.
/// The web build's stand-in for trusting the Quark's self-signed certificate. The browser owns TLS there, so this
/// does nothing.
void installLocalTrustHttpOverrides() {}
