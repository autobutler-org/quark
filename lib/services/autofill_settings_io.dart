/// The autofill setting's channel on Android (#3600).
///
/// Only Android has an autofill service behind `org.autobutler/autofill`;
/// iOS (#3598) and desktop builds, and tests on a desktop host, answer
/// unsupported without calling it.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:quark/services/autofill_settings.dart';

const _channel = MethodChannel(AutofillSettings.channelName);

/// Whether this process runs on Android. A test of the channel sets it.
@visibleForTesting
bool Function() isAndroid = () => Platform.isAndroid;

/// Asks Android whether Quark is the autofill service. A channel failure
/// reads as unsupported, so a broken channel never offers the setting.
Future<AutofillStatus> status() async {
  if (!isAndroid()) return AutofillStatus.unsupported;
  try {
    final answer = await _channel.invokeMethod<String>('status');
    return AutofillStatus.values.asNameMap()[answer] ??
        AutofillStatus.unsupported;
  } on PlatformException catch (e) {
    debugPrint('[autofill_settings] status failed: ${e.code}');
    return AutofillStatus.unsupported;
  } on MissingPluginException {
    return AutofillStatus.unsupported;
  }
}

/// Opens Android's screen for choosing the autofill service.
Future<void> openSettings() async {
  if (!isAndroid()) throw UnsupportedError('No autofill settings here');
  await _channel.invokeMethod<void>('openSettings');
}
