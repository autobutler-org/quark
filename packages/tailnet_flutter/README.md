# tailnet_flutter

An embedded tailnet node for a Flutter app on iOS and Android. The phone joins
the tailnet itself and exposes a loopback HTTP proxy. Desktop and web builds
link a stub and report the node unavailable.

Quark depends on this package by path. The Go library is `cmd/tsnetbridge`,
built by `hook/build.dart` when the app is built for iOS or Android. It has
its own `go.mod` (`tailscale.com` pinned to the same version as the repo
root). The C symbols are still `quark_tsnet_*` and the proxy header is still
`X-Quark-Tunnel-Token`. Renaming those, and moving the package to its own
repository, is the rest of #3637.

```dart
import 'package:tailnet_flutter/tailnet_flutter.dart';
```

IO code that attaches the proxy token imports
`package:tailnet_flutter/services/tunnel_token_client.dart`. That library uses
`dart:io`, so a web build must not import it.
