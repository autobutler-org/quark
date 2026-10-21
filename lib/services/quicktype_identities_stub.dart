/// Web stand-in for the QuickType identity store (#3599). A browser has no
/// QuickType bar, so nothing is stored, and this file does not call
/// `dart:io`.
library;

import 'package:quark/services/quicktype_identities.dart';

/// Never on web.
bool isSupported() => false;

/// Stores nothing on web.
Future<bool> replace(List<QuickTypeIdentity> identities) async => false;

/// Nothing to remove on web.
Future<void> clear() async {}
