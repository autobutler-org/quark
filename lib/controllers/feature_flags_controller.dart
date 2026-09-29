import 'package:flutter/foundation.dart';
import 'package:quark/models/feature_flag.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/feature_flags_service.dart';
import 'package:quark/utils/error_text.dart';

/// The Features tab of Settings (#2542): the beta flags and an admin flipping
/// one.
///
/// The flags themselves live in [AppSettings.featureFlags], which the drawer
/// and the router follow too; this adds which flags are being saved. The
/// service call arrives as a function parameter defaulting to the real one,
/// so a test passes a fake without a mocking library.
class FeatureFlagsController extends ChangeNotifier {
  /// Creates a controller over [flags], [AppSettings.featureFlags] unless
  /// overridden, saving through [FeatureFlagsService.setFlag] unless
  /// overridden.
  FeatureFlagsController({
    ValueNotifier<List<FeatureFlag>>? flags,
    Future<FeatureFlag> Function(String key, bool enabled) setFlag =
        FeatureFlagsService.setFlag,
  }) : _flags = flags ?? AppSettings.instance.featureFlags,
       _setFlag = setFlag {
    _flags.addListener(notifyListeners);
  }

  final ValueNotifier<List<FeatureFlag>> _flags;
  final Future<FeatureFlag> Function(String key, bool enabled) _setFlag;
  final Set<String> _saving = {};
  bool _disposed = false;

  /// Every flag in the Quark's registry. Empty between betas.
  List<FeatureFlag> get flags => _flags.value;

  /// Whether a change to the flag [key] is being saved.
  bool isSaving(String key) => _saving.contains(key);

  /// Turns the flag [key] on or off. Returns user-facing copy from [Errors]
  /// when the Quark refuses, or null once it is saved. A second call while
  /// [key] is saving does nothing.
  Future<String?> setFlag(String key, bool enabled) async {
    if (!_saving.add(key)) return null;
    notifyListeners();
    try {
      final saved = await _setFlag(key, enabled);
      _flags.value = [
        for (final flag in _flags.value) flag.key == key ? saved : flag,
      ];
      return null;
    } catch (e) {
      return Errors.message(e, 'change the feature');
    } finally {
      _saving.remove(key);
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _flags.removeListener(notifyListeners);
    super.dispose();
  }
}
