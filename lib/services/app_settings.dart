import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
// flutter_secure_storage requires a secure context (HTTPS) on web.
// We only use it on native platforms; on web we fall back to in-memory only.
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:quark/controllers/file_browser_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Matches an explicit URI scheme prefix (`https://`, `http://`, `ws://`, ...).
///
/// Requires the `://` so a schemeless `host:port` is not mistaken for a scheme
/// — `Uri.parse('quark.local:8080')` reads `quark.local` as the scheme, which
/// is exactly the misparse this normalization exists to prevent.
final _schemePrefix = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*://');

/// Ensures a host address carries an explicit scheme, defaulting to `https://`.
///
/// A quark serves TLS, so a bare hostname must resolve to `https://` — without
/// a scheme `Uri.parse` yields a path-only URI with no authority and the
/// request silently degrades to plain HTTP against port 80.
///
/// An address that already names a scheme is returned untouched: an explicit
/// `http://` the user typed stays `http://`. Empty and origin-relative
/// addresses (the web build stores `/`) are left alone — they have no host.
String normalizeHostAddress(String address) {
  final trimmed = address.trim();
  if (trimmed.isEmpty || trimmed.startsWith('/')) return trimmed;
  if (_schemePrefix.hasMatch(trimmed)) return trimmed;
  return 'https://$trimmed';
}

/// Base URL used when no host has been configured yet.
///
/// Matches the plain-HTTP dev target (`make serve/backend`), which serves
/// :8080 in insecure mode. Only ever reached when [AppSettings.activeHost] is
/// null — a configured host always wins.
const String defaultApiBaseUrl = 'http://localhost:8080';

/// The configured quark base URL, falling back to [defaultApiBaseUrl].
///
/// `API_BASE_URL` overrides the fallback at build time via
/// `--dart-define=API_BASE_URL=...`.
String get apiBaseUrl =>
    AppSettings.instance.activeHost ??
    const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: defaultApiBaseUrl,
    );

/// [apiBaseUrl] as a [Uri], with the Android emulator's loopback alias applied.
///
/// The emulator reaches the host machine at 10.0.2.2 rather than localhost, so
/// a loopback address is rewritten before any request goes out.
Uri get apiBaseUri {
  final uri = Uri.parse(apiBaseUrl);
  final isLoopback =
      uri.host == 'localhost' || uri.host == '127.0.0.1' || uri.host == '::1';
  if (!kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      isLoopback) {
    return uri.replace(host: '10.0.2.2');
  }
  return uri;
}

class HostEntry {
  final String name;
  final String hostAddress;
  HostEntry({required this.name, required this.hostAddress});

  Map<String, String> toJson() => {'name': name, 'hostAddress': hostAddress};

  static HostEntry fromJson(Map<String, dynamic> m) =>
      HostEntry(name: m['name'] ?? '', hostAddress: m['hostAddress'] ?? '');
}

class AppSettings {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.system);

  final ValueNotifier<bool> demoMode = ValueNotifier(false);

  List<HostEntry> _hosts = [];
  int _activeIndex = -1;

  /// Session tokens per Quark, keyed by [_hostKey].
  ///
  /// Per-host, not app-wide: a single token meant switching Quarks carried the
  /// old one along, so the router's gate believed you were signed in to a
  /// Quark you had never logged into. Against a reachable Quark that resolved
  /// itself — a 401 clears the token — but an unreachable one never answers at
  /// all, so the stale token stood and every page failed instead (#1645).
  Map<String, String> _sessionTokens = {};

  /// The username signed in on each Quark, keyed by [_hostKey].
  ///
  /// Not a secret, so it sits in plain preferences rather than secure storage
  /// alongside the token. Recorded so the account-deletion confirmation can
  /// name the account it is about to delete and check what the user typed
  /// before the request goes out (#1762).
  Map<String, String> _usernames = {};
  SharedPreferences? _prefs;

  /// Notifies listeners whenever the session token changes.
  /// The router listens to this to redirect to login when a 401 clears the token.
  final ValueNotifier<String?> sessionTokenNotifier = ValueNotifier(null);

  /// Whether terms have been accepted **for the current [activeHost]**.
  ///
  /// Derived state — never assign to it directly. It is recomputed by
  /// [_publishActiveHost] whenever the active host changes and by
  /// [acceptTerms]. The router listens to it to redirect to the terms page for
  /// a Quark the user hasn't accepted terms for yet.
  final ValueNotifier<bool> hasAcceptedTerms = ValueNotifier(false);

  /// Hosts the user has accepted the terms for, keyed by [_hostKey].
  Set<String> _acceptedTermsHosts = {};

  /// Notifies listeners whenever [activeHost] changes — a host added, edited,
  /// removed, or selected.
  ///
  /// The router listens to this so the terms/login gate re-runs the moment a
  /// Quark is connected for the first time. Without it the redirect only fired
  /// on the next unrelated navigation, so terms showed up late (#1623).
  final ValueNotifier<String?> activeHostNotifier = ValueNotifier(null);
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  /// Holds a JSON object of host key -> token. Pre-#1645 builds wrote a bare
  /// token string here instead; [load] migrates that onto the active host.
  static const _sessionTokenKey = 'session_token';
  static const _acceptedTermsHostsKey = 'acceptedTermsHosts';
  static const _demoModeKey = 'demoMode';

  /// Holds a JSON object of host key -> username. Absent for a session that
  /// predates it, and for one recovered by phrase, which never names a user.
  static const _usernamesKey = 'usernames';

  /// Pre-#1623 key: a single app-wide "terms accepted" bool. Read once on
  /// load and migrated into [_acceptedTermsHostsKey] so existing users aren't
  /// asked to re-accept for the Quark they're already using.
  static const _legacyAcceptedTermsKey = 'hasAcceptedTerms';

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final theme = _prefs!.getString('themeMode') ?? 'system';
    themeMode.value = theme == 'light'
        ? ThemeMode.light
        : theme == 'dark'
        ? ThemeMode.dark
        : ThemeMode.system;
    demoMode.value = _prefs!.getBool(_demoModeKey) ?? false;

    final hostsJson = _prefs!.getString('hosts') ?? '[]';
    try {
      final decoded = jsonDecode(hostsJson) as List;
      // Normalize on load, not just on add/update: an entry persisted by an
      // older build (or any path that skipped normalization) would otherwise
      // stay schemeless forever and keep resolving to plain HTTP.
      _hosts = decoded
          .map(
            (e) =>
                _normalizeHost(HostEntry.fromJson(e as Map<String, dynamic>)),
          )
          .toList();
    } catch (_) {
      debugPrint('[app_settings.dart] Error in catch block');
      _hosts = [];
    }

    _activeIndex =
        _prefs!.getInt('activeHostIndex') ?? (_hosts.isEmpty ? -1 : 0);

    // Read raw here, but decode below: a pre-#1645 bare token has to be
    // attributed to a host, and the active host is not settled until the
    // default-host block has run.
    final storedTokens = kIsWeb
        // On web, use shared_preferences (localStorage) — flutter_secure_storage
        // requires HTTPS and will fail over plain HTTP during development.
        ? _prefs!.getString(_sessionTokenKey)
        : await _secureStorage.read(key: _sessionTokenKey);

    final storedTermsHosts = _prefs!.getStringList(_acceptedTermsHostsKey);
    _acceptedTermsHosts = storedTermsHosts?.toSet() ?? {};

    _usernames = _decodeUsernames(_prefs!.getString(_usernamesKey));

    // If no hosts configured and running in debug (local development), add a local loopback
    // host appropriate for the running platform so developers can quickly connect.
    if (_hosts.isEmpty) {
      if (kDebugMode) {
        // Targets the plain-HTTP dev server (`make serve/backend`), which
        // listens on :8080 only in insecure mode. Scheme and port move
        // together: :8080 is never served over TLS, so `https://localhost:8080`
        // would connect to nothing. To develop against the secure server
        // (`make serve/backend/secure`, TLS on :443) point this at
        // `https://localhost` instead — its self-signed cert is accepted by
        // badCertificateCallback in AuthenticatedService for local-trust hosts.
        final loopback =
            !kIsWeb && defaultTargetPlatform == TargetPlatform.android
            ? 'http://10.0.2.2:8080'
            : 'http://localhost:8080';
        _hosts = [HostEntry(name: 'Local', hostAddress: loopback)];
        _activeIndex = 0;
        await _saveHosts();
      } else if (kIsWeb) {
        // Otherwise, add a default that targets the URL it is the web version
        _hosts = [HostEntry(name: 'Default', hostAddress: '/')];
        _activeIndex = 0;
        await _saveHosts();
      }
    }

    // Decode the token store now that the active host is settled. A JSON object
    // is the current shape; anything else is the pre-#1645 bare token string,
    // which belongs to whichever Quark the user was last on. With no host to
    // attribute it to we leave it for a later launch, exactly as the legacy
    // terms bool below does.
    final legacyToken = _decodeSessionTokens(storedTokens);
    if (legacyToken != null && activeHost != null) {
      _sessionTokens[_hostKey(activeHost!)] = legacyToken;
      await _persistSessionTokens();
    }

    // Migrate the legacy app-wide bool now that the active host is settled.
    // Only migrate once there is a host to attribute the acceptance to — with
    // none configured we leave the legacy key for a later launch to pick up.
    if (storedTermsHosts == null &&
        (_prefs!.getBool(_legacyAcceptedTermsKey) ?? false)) {
      final host = activeHost;
      if (host != null) {
        _acceptedTermsHosts.add(_hostKey(host));
        await _persistAcceptedTermsHosts();
        await _prefs!.remove(_legacyAcceptedTermsKey);
      }
    }

    _publishActiveHost();
  }

  List<HostEntry> get hosts => List.unmodifiable(_hosts);
  int get activeIndex => _activeIndex;

  /// Session token for the current [activeHost], set after a successful login
  /// or setup. Persisted — survives app restarts.
  /// Populated by [AuthService] after login/setup; consumed by [FilesService].
  ///
  /// Null for a Quark the user has never signed into, which is what sends them
  /// to login on switching hosts without waiting on a 401 that an unreachable
  /// Quark would never send (#1645).
  String? get sessionToken => sessionTokenFor(activeHost);

  /// Session token stored for [hostAddress], if any.
  String? sessionTokenFor(String? hostAddress) =>
      hostAddress == null ? null : _sessionTokens[_hostKey(hostAddress)];

  /// Stores [token] against the current [activeHost], or clears it when null.
  ///
  /// With no host configured there is nothing to attribute a token to, so
  /// storage is left alone — but the notifier still publishes the null that
  /// [sessionToken] now reports.
  Future<void> setSessionToken(String? token) async {
    final host = activeHost;
    if (host != null && token != sessionToken) {
      if (token != null) {
        _sessionTokens[_hostKey(host)] = token;
      } else {
        _sessionTokens.remove(_hostKey(host));
      }
      await _persistSessionTokens();
    }
    sessionTokenNotifier.value = sessionToken;
  }

  /// The username signed in on the current [activeHost], or null when this
  /// Quark's session predates the app recording it (or was recovered by
  /// phrase, which never names a user).
  String? get username => usernameFor(activeHost);

  /// The username stored for [hostAddress], if any.
  String? usernameFor(String? hostAddress) =>
      hostAddress == null ? null : _usernames[_hostKey(hostAddress)];

  /// Stores [name] against the current [activeHost], or forgets it when null.
  Future<void> setUsername(String? name) async {
    final host = activeHost;
    if (host == null || name == username) return;
    if (name != null) {
      _usernames[_hostKey(host)] = name;
    } else {
      _usernames.remove(_hostKey(host));
    }
    await _prefs?.setString(_usernamesKey, jsonEncode(_usernames));
  }

  Map<String, String> _decodeUsernames(String? stored) {
    if (stored == null || stored.isEmpty) return {};
    try {
      final decoded = jsonDecode(stored);
      if (decoded is Map) return decoded.map((k, v) => MapEntry('$k', '$v'));
    } catch (_) {
      debugPrint('[app_settings.dart] Unreadable username store');
    }
    return {};
  }

  /// Reads [stored] into [_sessionTokens].
  ///
  /// Returns a pre-#1645 bare token string when that is what was stored, for
  /// the caller to attribute to a host; null when the store was already a map,
  /// empty, or unreadable.
  String? _decodeSessionTokens(String? stored) {
    // Reassigned, never merged: [load] rebuilds every other field from the
    // store too, and keeping stale entries would leave a signed-out user
    // holding a token the store no longer has.
    _sessionTokens = {};
    if (stored == null || stored.isEmpty) return null;
    try {
      final decoded = jsonDecode(stored);
      if (decoded is Map) {
        _sessionTokens = decoded.map((k, v) => MapEntry('$k', '$v'));
        return null;
      }
    } catch (_) {
      // Not JSON at all — a bare token from a pre-#1645 build.
    }
    return stored;
  }

  Future<void> _persistSessionTokens() async {
    final encoded = jsonEncode(_sessionTokens);
    if (kIsWeb) {
      // Use shared_preferences (localStorage) on web — flutter_secure_storage
      // requires HTTPS and fails over plain HTTP in development.
      await _prefs?.setString(_sessionTokenKey, encoded);
    } else {
      await _secureStorage.write(key: _sessionTokenKey, value: encoded);
    }
  }

  String? get activeHost => (_activeIndex >= 0 && _activeIndex < _hosts.length)
      ? _hosts[_activeIndex].hostAddress
      : null;

  /// Publishes the current [activeHost] to [activeHostNotifier] and recomputes
  /// [hasAcceptedTerms] for it.
  /// Every mutation of [_hosts] or [_activeIndex] must end with this call.
  ///
  /// [hasAcceptedTerms] is updated first so that a listener woken by either
  /// notifier sees both values already consistent with each other.
  void _publishActiveHost() {
    final host = activeHost;
    hasAcceptedTerms.value =
        host != null && _acceptedTermsHosts.contains(_hostKey(host));
    // Tokens are per-host, so switching Quarks changes what [sessionToken]
    // reports; republish so no listener is left holding the old host's.
    sessionTokenNotifier.value = sessionToken;
    activeHostNotifier.value = host;
  }

  /// Normalized lookup key for a host address, so `https://Quark.local` and
  /// `https://quark.local/` count as the same Quark. Keys both the accepted
  /// terms and the session tokens.
  static String _hostKey(String hostAddress) {
    final trimmed = hostAddress.trim().toLowerCase();
    final withoutTrailingSlashes = trimmed.replaceAll(RegExp(r'/+$'), '');
    return withoutTrailingSlashes.isEmpty ? trimmed : withoutTrailingSlashes;
  }

  Future<void> _persistAcceptedTermsHosts() async {
    await _prefs?.setStringList(
      _acceptedTermsHostsKey,
      _acceptedTermsHosts.toList(),
    );
  }

  /// Whether the terms have been accepted for [hostAddress].
  bool hasAcceptedTermsFor(String hostAddress) =>
      _acceptedTermsHosts.contains(_hostKey(hostAddress));

  Future<void> _saveHosts() async {
    await _prefs?.setString(
      'hosts',
      jsonEncode(_hosts.map((e) => e.toJson()).toList()),
    );
    await _prefs?.setInt('activeHostIndex', _activeIndex);
    _publishActiveHost();
  }

  Future<void> addHost(HostEntry h) async {
    _hosts.add(_normalizeHost(h));
    _activeIndex = _hosts.length - 1;
    await _saveHosts();
  }

  Future<void> updateHost(int idx, HostEntry h) async {
    if (idx >= 0 && idx < _hosts.length) {
      _hosts[idx] = _normalizeHost(h);
      await _saveHosts();
    }
  }

  /// Ensures the host address has a scheme, defaulting bare hostnames to
  /// `https://`. See [normalizeHostAddress].
  HostEntry _normalizeHost(HostEntry h) {
    final normalized = normalizeHostAddress(h.hostAddress);
    if (normalized == h.hostAddress) return h;
    return HostEntry(name: h.name, hostAddress: normalized);
  }

  Future<void> removeHost(int idx) async {
    if (idx >= 0 && idx < _hosts.length) {
      // Forgetting a Quark forgets the session with it. Only touches storage
      // when there was actually a token — a host nobody signed into must not
      // drag the secure-storage plugin into the call.
      if (_sessionTokens.remove(_hostKey(_hosts[idx].hostAddress)) != null) {
        await _persistSessionTokens();
      }
      if (_usernames.remove(_hostKey(_hosts[idx].hostAddress)) != null) {
        await _prefs?.setString(_usernamesKey, jsonEncode(_usernames));
      }
      _hosts.removeAt(idx);
      if (_activeIndex >= _hosts.length) {
        _activeIndex = _hosts.length - 1;
      }
      await _saveHosts();
    }
  }

  Future<void> setActiveIndex(int idx) async {
    if (idx >= 0 && idx < _hosts.length) {
      _activeIndex = idx;
      // Clear cached file listings — they belong to the previous host.
      FileBrowserCache.instance.clear();
      await _prefs?.setInt('activeHostIndex', _activeIndex);
      _publishActiveHost();
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode.value = mode;
    final key = mode == ThemeMode.light
        ? 'light'
        : mode == ThemeMode.dark
        ? 'dark'
        : 'system';
    await _prefs?.setString('themeMode', key);
  }

  Future<void> setDemoMode(bool enabled) async {
    demoMode.value = enabled;
    await _prefs?.setBool(_demoModeKey, enabled);
  }

  /// Records acceptance of the Terms and Conditions for the current
  /// [activeHost] and persists it.
  ///
  /// Acceptance is per-Quark: connecting to a backend the user hasn't accepted
  /// terms for shows the terms page again (#1623). With no host configured
  /// there is nothing to attribute the acceptance to — the router's gate lets
  /// that state through anyway, so this is a no-op.
  Future<void> acceptTerms() async {
    final host = activeHost;
    if (host == null) return;
    _acceptedTermsHosts.add(_hostKey(host));
    await _persistAcceptedTermsHosts();
    _publishActiveHost();
  }

  /// Auto-refresh interval in seconds. 0 = disabled.
  int get refreshIntervalSeconds =>
      _prefs?.getInt('refreshIntervalSeconds') ?? 15;

  Future<void> setRefreshIntervalSeconds(int seconds) async {
    await _prefs?.setInt('refreshIntervalSeconds', seconds);
  }
}
