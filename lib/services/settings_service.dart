import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';

/// Calls `/api/v0/settings` for the Quark's settings and the signed-in user's
/// own, such as the theme color (#2740) and the personal preferences that
/// follow the account across devices (#1914).
class SettingsService with AuthenticatedService {
  static final SettingsService _instance = SettingsService._();
  SettingsService._();
  static SettingsService get instance => _instance;

  /// The Quark's default theme color as its storage string, empty when its admin
  /// has not chosen one. `GET /settings/public` needs no session, so the
  /// sign-in page can ask.
  static Future<String> getQuarkThemeColor() async {
    final response = await instance.httpClient.get(
      apiBaseUri.resolve('/api/v0/settings/public'),
    );
    return _themeColorOf(
      _readSettings(response, 'Failed to fetch public settings'),
    );
  }

  /// Sets the Quark's default theme color to the storage string [themeColor]; empty
  /// clears it. Admin-only.
  static Future<void> setQuarkThemeColor(String themeColor) async {
    final response = await instance.authenticatedPut(
      apiBaseUri.resolve('/api/v0/settings/theme-color'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'themeColor': themeColor}),
    );
    _readSettings(response, 'Failed to save the theme color');
  }

  /// The signed-in user's own theme color as its storage string, empty when they
  /// follow the Quark's.
  static Future<String> getMyThemeColor() async =>
      _themeColorOf(await getMySettings());

  /// Sets the signed-in user's own theme color to the storage string [themeColor];
  /// empty follows the Quark's. Every other setting is kept, see
  /// [updateMySettings].
  static Future<void> setMyThemeColor(String themeColor) =>
      updateMySettings((current) => {...current, 'themeColor': themeColor});

  /// The signed-in user's own settings as the Quark holds them: `themeColor`,
  /// `disabledNotifications` (left out when every type is on), and whatever
  /// a newer Quark adds.
  static Future<Map<String, dynamic>> getMySettings() async {
    final response = await instance.authenticatedGet(
      apiBaseUri.resolve(_mySettingsPath),
    );
    return _readSettings(response, 'Failed to fetch your settings');
  }

  /// Saves the signed-in user's own settings as [change] makes them from the
  /// current ones, and returns what the Quark saved.
  ///
  /// `PUT /settings/me` replaces the settings whole, so every write of one
  /// field goes through here: it reads first and sends the rest back
  /// unchanged. A theme color save that sent only the color would turn every
  /// notification type back on (#2493).
  static Future<Map<String, dynamic>> updateMySettings(
    Map<String, dynamic> Function(Map<String, dynamic> current) change,
  ) async {
    final settings = change(await getMySettings());
    final response = await instance.authenticatedPut(
      apiBaseUri.resolve(_mySettingsPath),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(settings),
    );
    return _readSettings(response, 'Failed to save your settings');
  }

  static const _mySettingsPath = '/api/v0/settings/me';

  static String _themeColorOf(Map<String, dynamic> settings) =>
      settings['themeColor'] is String ? settings['themeColor'] as String : '';

  /// The settings object in [response], empty when the body is not one.
  /// Throws an [ApiException] carrying [context] for a non-success status.
  static Map<String, dynamic> _readSettings(
    http.Response response,
    String context,
  ) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, context);
    }
    final decoded = jsonDecode(response.body);
    return decoded is Map<String, dynamic> ? decoded : {};
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

  /// Sets the theme mode on this device and, signed in, on the account.
  ///
  /// This and its siblings apply the change locally first, so it stays even
  /// when the save to the account then throws.
  static Future<void> setMyThemeMode(ThemeMode mode) async {
    await AppSettings.instance.setThemeMode(mode);
    await _saveMyPersonalSettings({_themeModeKey: mode.name});
  }

  /// Sets the auto-refresh interval, see [setMyThemeMode].
  static Future<void> setMyRefreshIntervalSeconds(int seconds) async {
    await AppSettings.instance.setRefreshIntervalSeconds(seconds);
    await _saveMyPersonalSettings({_refreshIntervalKey: seconds});
  }

  /// Sets the document editor's auto-save, see [setMyThemeMode].
  static Future<void> setMyDocumentAutoSave(bool enabled) async {
    await AppSettings.instance.setDocumentAutoSave(enabled);
    await _saveMyPersonalSettings({_documentAutoSaveKey: enabled});
  }

  /// Sets the document editor's dark page, see [setMyThemeMode].
  static Future<void> setMyDocumentDarkPage(bool enabled) async {
    await AppSettings.instance.setDocumentDarkPage(enabled);
    await _saveMyPersonalSettings({_documentDarkPageKey: enabled});
  }

  /// Awaits [save], one of the `setMy…` calls, for a caller with nowhere to
  /// show a failed save to the account: it is logged, and the change stays
  /// on this device.
  static Future<void> logFailure(Future<void> save) async {
    try {
      await save;
    } catch (e) {
      debugPrint('[settings_service.dart] saving a personal setting: $e');
    }
  }

  /// Syncs the personal preferences with the signed-in account (#1914).
  ///
  /// Each one the account holds replaces this device's. Each one it lacks is
  /// sent from this device, all in one save, so the first device an account
  /// signs in on after an upgrade sets its values. [AppSettings] keeps the
  /// result on the device for the first frame, offline, and the sign-in page.
  ///
  /// Never throws, and drops an answer that arrives after the host or the
  /// session changed, as [refreshThemeColor] does.
  static Future<void> refreshPersonalSettings() async {
    final settings = AppSettings.instance;
    final host = settings.activeHost;
    final token = settings.sessionToken;
    if (host == null || token == null) return;
    bool current() =>
        settings.activeHost == host && settings.sessionToken == token;
    try {
      final mine = await getMySettings();
      if (!current()) return;
      final missing = {
        for (final entry in _localPersonalSettings(settings).entries)
          if (!mine.containsKey(entry.key)) entry.key: entry.value,
      };
      final themeMode = ThemeMode.values.asNameMap()[mine[_themeModeKey]];
      if (themeMode != null) await settings.setThemeMode(themeMode);
      final interval = mine[_refreshIntervalKey];
      if (interval is int) await settings.setRefreshIntervalSeconds(interval);
      final autoSave = mine[_documentAutoSaveKey];
      if (autoSave is bool) await settings.setDocumentAutoSave(autoSave);
      final darkPage = mine[_documentDarkPageKey];
      if (darkPage is bool) await settings.setDocumentDarkPage(darkPage);
      if (missing.isEmpty || !current()) return;
      // What another device saved in the meantime wins over this one's.
      await updateMySettings((latest) => {...missing, ...latest});
    } catch (e) {
      debugPrint('[settings_service.dart] refreshPersonalSettings failed: $e');
    }
  }

  static const _themeModeKey = 'themeMode';
  static const _refreshIntervalKey = 'refreshIntervalSeconds';
  static const _documentAutoSaveKey = 'documentAutoSave';
  static const _documentDarkPageKey = 'documentDarkPage';

  static Map<String, Object> _localPersonalSettings(AppSettings settings) => {
    _themeModeKey: settings.themeMode.value.name,
    _refreshIntervalKey: settings.refreshIntervalSeconds,
    _documentAutoSaveKey: settings.documentAutoSave.value,
    _documentDarkPageKey: settings.documentDarkPage.value,
  };

  /// Merges [fields] into the signed-in account's settings. Signed out it
  /// does nothing: [refreshPersonalSettings] uploads them at sign-in.
  static Future<void> _saveMyPersonalSettings(
    Map<String, Object> fields,
  ) async {
    if (AppSettings.instance.sessionToken == null) return;
    await updateMySettings((current) => {...current, ...fields});
  }
}
