import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:quark/models/feature_flag.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';

/// The beta feature flags API, `/api/v0/settings/features` (#2542). Any
/// signed-in user may list the flags; only an admin may flip one.
class FeatureFlagsService with AuthenticatedService {
  FeatureFlagsService._();

  /// The shared instance, which carries the session.
  static final FeatureFlagsService instance = FeatureFlagsService._();

  /// Every flag in the Quark's registry and whether it is on.
  static Future<List<FeatureFlag>> list() async {
    final response = await instance.authenticatedGet(
      apiBaseUri.resolve('/api/v0/settings/features'),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Failed to list features');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return [
      for (final entry in body['features'] as List? ?? const [])
        FeatureFlag.fromJson(entry as Map<String, dynamic>),
    ];
  }

  /// Turns the flag [key] on or off for everyone and returns it as the Quark
  /// saved it. Admin-only.
  static Future<FeatureFlag> setFlag(String key, bool enabled) async {
    final response = await instance.authenticatedPut(
      apiBaseUri.resolve(
        '/api/v0/settings/features/${Uri.encodeComponent(key)}',
      ),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'enabled': enabled}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Failed to set feature $key');
    }
    return FeatureFlag.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Fetches the flags into [AppSettings.featureFlags], so the drawer and the
  /// router follow them. Without a session there are none; a failed call
  /// keeps the last known flags.
  static Future<void> refresh() async {
    final settings = AppSettings.instance;
    if (settings.sessionToken == null) {
      settings.featureFlags.value = const [];
      return;
    }
    try {
      settings.featureFlags.value = await list();
    } catch (e) {
      debugPrint('[feature_flags_service.dart] refresh failed: $e');
    }
  }
}
