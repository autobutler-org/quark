/// How a Quark's address reads in the app's chrome (#2033).
///
/// The stored address is a URL — `https://quark.home.local/` — and the chrome
/// has a drawer header's width to say which device is on screen. The scheme is
/// the same on every entry and a trailing slash is noise, so neither earns its
/// space; a port does, because two Quarks on one machine differ only by it.
///
/// Anything that is not a URL with a host (the web build stores `/`) comes
/// back trimmed rather than mangled — better to show what was stored than to
/// invent a name for it.
String shortHostAddress(String? address) {
  final trimmed = (address ?? '').trim();
  if (trimmed.isEmpty) return '';

  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.host.isEmpty) {
    return trimmed.replaceAll(RegExp(r'/+$'), '');
  }
  return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
}
