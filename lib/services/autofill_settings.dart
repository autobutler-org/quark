import 'package:quark/services/autofill_settings_stub.dart'
    if (dart.library.io) 'package:quark/services/autofill_settings_io.dart'
    as impl;

/// Whether Quark fills passwords in other apps on this device.
enum AutofillStatus {
  /// Quark is the device's autofill service.
  enabled,

  /// The device has autofill, and another service or none is chosen.
  disabled,

  /// Web, desktop, iOS, or an Android before 8 or without autofill.
  unsupported,
}

/// Android's system autofill setting for Quark (#3600), over the
/// `org.autobutler/autofill` channel (`org.autobutler.autofill.AutofillSettings`).
///
/// [status] says whether Quark is the chosen service, and [openSettings]
/// opens the system screen that chooses it. Everywhere but Android the
/// status is [AutofillStatus.unsupported] and nothing is opened.
abstract final class AutofillSettings {
  /// The platform channel's name.
  static const channelName = 'org.autobutler/autofill';

  /// Whether Quark is this device's autofill service.
  static Future<AutofillStatus> status() => impl.status();

  /// Opens the system screen that makes Quark the autofill service. Throws
  /// when the device has none.
  static Future<void> openSettings() => impl.openSettings();
}
