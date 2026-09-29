import 'package:quark/utils/local_time_zone_stub.dart'
    if (dart.library.js_interop) 'package:quark/utils/local_time_zone_web.dart';

/// The IANA name of the device's time zone, such as `America/Los_Angeles`, or
/// an empty string where the platform does not say.
///
/// A browser knows it. iOS and Android need a plugin to ask, which is left to
/// the server-side reminders work (#2525), so they send an empty name for now.
/// The Quark records it with each event and nothing reads it yet.
String get localTimeZoneName => localTimeZoneNamePlatform;
