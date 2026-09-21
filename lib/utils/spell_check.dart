import 'package:flutter/widgets.dart';

/// Spell checking for a field people write prose in.
///
/// Flutter's spell check is the platform's, and only iOS and Android provide
/// one. Elsewhere, web included, a configuration with no service is dropped and
/// reported as a [FlutterError] in debug builds, so this returns an enabled
/// configuration only where the platform will honor it.
SpellCheckConfiguration proseSpellCheck() =>
    WidgetsBinding.instance.platformDispatcher.nativeSpellCheckServiceDefined
    ? const SpellCheckConfiguration()
    : const SpellCheckConfiguration.disabled();
