import 'package:flutter/material.dart';
import 'package:quark/models/feature_flag.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The Features tab of Settings (#2542): a switch per beta feature flag, for
/// admins only.
///
/// The page shows it only while the Quark has betas, and owns the flags and
/// which are being saved; this tab renders them and reports a flip.
class SettingsFeaturesTab extends StatelessWidget {
  /// Creates the tab.
  const SettingsFeaturesTab({
    required this.flags,
    required this.isSaving,
    required this.onChanged,
    this.header,
    super.key,
  });

  /// Every flag in the Quark's registry.
  final List<FeatureFlag> flags;

  /// Whether a change to the flag with this key is being saved. Holds its
  /// switch still.
  final bool Function(String key) isSaving;

  /// Called with a flag's key and the value an admin picked.
  final void Function(String key, bool enabled) onChanged;

  /// Shown above the tab's content and scrolled with it, such as the
  /// page's disconnected banner; null shows nothing.
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (header != null) ...[header!, const SizedBox(height: 24)],
        for (final flag in flags)
          FeatureFlagTile(
            flagKey: flag.key,
            label: flag.label,
            description: flag.description,
            enabled: flag.enabled,
            isBusy: isSaving(flag.key),
            onChanged: (enabled) => onChanged(flag.key, enabled),
          ),
      ],
    );
  }
}
