import 'package:quark_widgets/quark_widgets.dart';

/// Whether the phone's account button shows its dot (#4150): something
/// behind it wants a look.
///
/// That is an unread notification ([notifications] above zero), a running
/// job or upload ([running] above zero), or a Quark this app cannot fully
/// reach: remote access [paused] on this phone, or [mode] offline. A [mode]
/// of null, the web or no Quark yet, is no reason on its own.
bool accountDotShown({
  required int notifications,
  required int running,
  required ConnectionMode? mode,
  required bool paused,
}) =>
    notifications > 0 ||
    running > 0 ||
    paused ||
    mode == ConnectionMode.offline;
