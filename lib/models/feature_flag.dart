import 'package:flutter/foundation.dart';

/// One beta feature flag from the Quark's registry (#2542), joined with
/// whether it is on.
///
/// A flag exists only while its feature is in beta: when the feature ships,
/// the flag and every check against it are deleted.
@immutable
class FeatureFlag {
  /// Creates a flag.
  const FeatureFlag({
    required this.key,
    required this.label,
    required this.description,
    required this.enabled,
  });

  /// Reads one entry of `GET /api/v0/settings/features`.
  factory FeatureFlag.fromJson(Map<String, dynamic> json) => FeatureFlag(
    key: json['key'] as String? ?? '',
    label: json['label'] as String? ?? '',
    description: json['description'] as String? ?? '',
    enabled: json['enabled'] as bool? ?? false,
  );

  /// The key of the chat beta (#2414).
  static const chat = 'chat';

  /// The flag's stable key, such as [chat].
  final String key;

  /// The feature's name, for admins.
  final String label;

  /// What the flag does, including what turning it off actually means.
  final String description;

  /// Whether the flag is on on this Quark.
  final bool enabled;
}
