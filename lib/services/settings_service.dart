import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';

/// Calls `/api/v0/settings` for the Quark's settings, such as automatic updates
/// and the theme color (#2740).
class SettingsService with AuthenticatedService {
  static final SettingsService _instance = SettingsService._();
  SettingsService._();
  static SettingsService get instance => _instance;

  static Future<bool> getAutoUpdate() async {
    final uri = apiBaseUri.resolve('/api/v0/settings');
    final response = await instance.authenticatedGet(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Failed to fetch settings');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid settings response format');
    }
    final data = decoded['data'];
    final map = data is Map<String, dynamic> ? data : decoded;
    return map['autoUpdate'] as bool? ?? false;
  }

  static Future<void> setAutoUpdate(bool enabled) async {
    final uri = apiBaseUri.resolve('/api/v0/settings');
    final body = jsonEncode({'autoUpdate': enabled});
    final response = await instance.authenticatedPost(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Failed to update settings');
    }
  }

  /// The Quark's default theme color as its storage string, empty when its admin
  /// has not chosen one. `GET /settings/public` needs no session, so the
  /// sign-in page can ask.
  static Future<String> getQuarkThemeColor() async {
    final response = await instance.httpClient.get(
      apiBaseUri.resolve('/api/v0/settings/public'),
    );
    return _readThemeColor(response, 'Failed to fetch public settings');
  }

  /// Sets the Quark's default theme color to the storage string [themeColor]; empty
  /// clears it. Admin-only.
  static Future<void> setQuarkThemeColor(String themeColor) =>
      _putThemeColor('/api/v0/settings/theme-color', themeColor);

  /// The signed-in user's own theme color as its storage string, empty when they
  /// follow the Quark's.
  static Future<String> getMyThemeColor() async {
    final response = await instance.authenticatedGet(
      apiBaseUri.resolve('/api/v0/settings/me'),
    );
    return _readThemeColor(response, 'Failed to fetch your settings');
  }

  /// Sets the signed-in user's own theme color to the storage string [themeColor];
  /// empty follows the Quark's.
  static Future<void> setMyThemeColor(String themeColor) =>
      _putThemeColor('/api/v0/settings/me', themeColor);

  static Future<void> _putThemeColor(String path, String themeColor) async {
    final response = await instance.authenticatedPut(
      apiBaseUri.resolve(path),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'themeColor': themeColor}),
    );
    _readThemeColor(response, 'Failed to save the theme color');
  }

  static String _readThemeColor(http.Response response, String context) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, context);
    }
    final decoded = jsonDecode(response.body);
    return decoded is Map && decoded['themeColor'] is String
        ? decoded['themeColor'] as String
        : '';
  }

  /// Fetches the active Quark's default theme color and, with a session, the
  /// user's own into [AppSettings], which resolves the two into the theme.
  ///
  /// Never throws: a failed call keeps what is known, so the app stays on
  /// the cached theme color and signing in is never held up by a color. An answer
  /// that arrives after the host or the session changed is dropped.
  static Future<void> refreshThemeColor() async {
    final settings = AppSettings.instance;
    final host = settings.activeHost;
    final token = settings.sessionToken;
    if (host == null) return;
    if (token == null) await settings.setUserThemeColor(null);

    Future<void> load(
      Future<String> Function() fetch,
      Future<void> Function(String?) apply,
    ) async {
      try {
        final themeColor = await fetch();
        if (settings.activeHost == host && settings.sessionToken == token) {
          await apply(themeColor);
        }
      } catch (e) {
        debugPrint('[settings_service.dart] refreshThemeColor failed: $e');
      }
    }

    await Future.wait([
      load(getQuarkThemeColor, settings.setQuarkThemeColor),
      if (token != null) load(getMyThemeColor, settings.setUserThemeColor),
    ]);
  }
}
