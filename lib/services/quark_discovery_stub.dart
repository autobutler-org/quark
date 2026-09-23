import 'package:quark/services/quark_discovery.dart';

/// The web build's browser: none. Browsers cannot browse mDNS, so the web
/// client only takes a typed address.
QuarkBrowser? get quarkBrowser => null;
