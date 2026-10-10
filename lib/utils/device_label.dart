/// The name a person would give the client behind [userAgent], such as
/// "Chrome on macOS" or "Quark app", for the Connected devices list (#2051).
///
/// A browser reads as its name and its platform. The Quark app's own client
/// is "Quark app", any other tool goes by its product token ("curl"), and an
/// empty [userAgent] is "Unknown device".
String deviceLabel(String userAgent) {
  final browser = _browser(userAgent);
  final platform = _firstMatch(_platforms, userAgent);
  if (browser != null) {
    return platform == null ? browser : '$browser on $platform';
  }
  if (userAgent.startsWith('Dart/')) return 'Quark app';
  if (platform != null) return platform;
  final product = userAgent.split(RegExp('[/ ]')).first;
  return product.isEmpty ? 'Unknown device' : product;
}

/// What to call the client behind [userAgent] when it is the one looking at
/// the list: "This browser", or "This device" for anything else.
String currentDeviceLabel(String userAgent) =>
    _browser(userAgent) == null ? 'This device' : 'This browser';

// ponytail: substring checks, first hit wins. An iPad asking for the desktop
// site reports itself as a Mac; client hints are the upgrade if that matters.
const _browsers = {
  // Chromium browsers also say Chrome and Safari, so they go first.
  'Edg': 'Edge',
  'OPR/': 'Opera',
  'Firefox': 'Firefox',
  'FxiOS': 'Firefox',
  'Chrome': 'Chrome',
  'CriOS': 'Chrome',
  'Safari': 'Safari',
};

const _platforms = {
  // iPhone and iPad also say Mac OS X, and Android says Linux.
  'iPhone': 'iPhone',
  'iPad': 'iPad',
  'Android': 'Android',
  'CrOS': 'ChromeOS',
  'Windows': 'Windows',
  'Mac OS X': 'macOS',
  'Macintosh': 'macOS',
  'Linux': 'Linux',
};

String? _browser(String userAgent) =>
    userAgent.startsWith('Mozilla/') ? _firstMatch(_browsers, userAgent) : null;

String? _firstMatch(Map<String, String> names, String userAgent) {
  for (final MapEntry(key: token, value: name) in names.entries) {
    if (userAgent.contains(token)) return name;
  }
  return null;
}
