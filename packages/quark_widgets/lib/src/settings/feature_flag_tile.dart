import 'package:flutter/material.dart';

import '../core/quark_beta_badge.dart';
import '../theme/quark_tokens.dart';

/// The switch for one beta feature flag: its label with a [QuarkBetaBadge],
/// what turning it off does, and whether it is on.
///
/// Whether the flag is on is the caller's state, [enabled] in and
/// [onChanged] out. While [isBusy] the switch holds still, so a second tap
/// cannot race the first.
///
/// Key prefixes: `feature_flag_tile_<flagKey>` on the switch row, for
/// example `feature_flag_tile_chat`.
///
/// ```dart
/// FeatureFlagTile(
///   flagKey: 'chat',
///   label: 'Chat',
///   description: 'Hides the feature; stored data is kept.',
///   enabled: controller.isEnabled('chat'),
///   isBusy: controller.isSaving('chat'),
///   onChanged: (on) => controller.setFlag('chat', on),
/// );
/// ```
class FeatureFlagTile extends StatelessWidget {
  /// Creates the switch for the flag [flagKey], showing [enabled].
  const FeatureFlagTile({
    required this.flagKey,
    required this.label,
    required this.description,
    required this.enabled,
    this.isBusy = false,
    this.onChanged,
    super.key,
  });

  /// The flag's stable key, such as `chat`. Builds the row's `ValueKey`.
  final String flagKey;

  /// The feature's name, shown next to the beta badge.
  final String label;

  /// What the flag does, including what turning it off actually means.
  final String description;

  /// Whether the flag is on.
  final bool enabled;

  /// Whether a change is being saved. Disables the switch.
  final bool isBusy;

  /// Called with the new value when the switch is flipped. Null disables the
  /// switch.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);

    return SwitchListTile(
      key: ValueKey('feature_flag_tile_$flagKey'),
      contentPadding: EdgeInsets.zero,
      title: Row(
        spacing: tokens.spacingSm,
        children: [
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          const QuarkBetaBadge(),
        ],
      ),
      subtitle: Text(
        description,
        style: TextStyle(color: tokens.mutedForeground),
      ),
      value: enabled,
      onChanged: isBusy ? null : onChanged,
    );
  }
}
