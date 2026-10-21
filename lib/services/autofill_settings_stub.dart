/// Web stand-in for the autofill setting's channel (#3600). A browser has
/// its own password filling, so Quark's is unsupported there. This file
/// does not call `dart:io`.
library;

import 'package:quark/services/autofill_settings.dart';

/// Always unsupported on web.
Future<AutofillStatus> status() async => AutofillStatus.unsupported;

/// Refuses: there is no system setting to open.
Future<void> openSettings() async =>
    throw UnsupportedError('No autofill settings on web');
