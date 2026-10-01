import 'dart:js_interop';

@JS('Intl.DateTimeFormat')
extension type _DateTimeFormat._(JSObject _) implements JSObject {
  external factory _DateTimeFormat();
  external _ResolvedOptions resolvedOptions();
}

extension type _ResolvedOptions._(JSObject _) implements JSObject {
  external String? get timeZone;
}

/// Web: the browser's own zone, from `Intl.DateTimeFormat`.
String get localTimeZoneNamePlatform {
  try {
    return _DateTimeFormat().resolvedOptions().timeZone ?? '';
  } catch (_) {
    return '';
  }
}
