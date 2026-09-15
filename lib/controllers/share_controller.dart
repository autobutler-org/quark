import 'package:flutter/foundation.dart';
import 'package:quark/models/path_grant.dart';
import 'package:quark/services/sharing_service.dart';
import 'package:quark_widgets/quark_widgets.dart';

typedef LoadAccessFn =
    Future<PathAccess> Function({
      required String deviceSerial,
      required String relPath,
    });
typedef LoadPrincipalsFn = Future<SharePrincipals> Function();
typedef GrantAccessFn =
    Future<PathAccess> Function({
      required String deviceSerial,
      required String relPath,
      int? userId,
      int? groupId,
      required String level,
    });
typedef RevokeAccessFn =
    Future<PathAccess> Function({
      required String deviceSerial,
      required String relPath,
      int? userId,
      int? groupId,
    });

/// State behind the share sheet for one file or folder (#1911): who has
/// access, who it can be shared with, and changing either.
///
/// Service calls arrive as function parameters defaulting to
/// [SharingService], so a test passes fakes without a mocking library. The
/// Quark answers every change with the whole access list, which replaces the
/// state. Failures come back raw; the host turns them into copy with
/// `Errors`.
class ShareController extends ChangeNotifier {
  ShareController({
    required this.deviceSerial,
    required this.relPath,
    this.selfUsername,
    this.isAdmin = false,
    LoadAccessFn loadAccess = SharingService.load,
    LoadPrincipalsFn loadPrincipals = SharingService.principals,
    GrantAccessFn grantAccess = SharingService.grant,
    RevokeAccessFn revokeAccess = SharingService.revoke,
  }) : _loadAccess = loadAccess,
       _loadPrincipals = loadPrincipals,
       _grantAccess = grantAccess,
       _revokeAccess = revokeAccess;

  /// The device the item is on.
  final String deviceSerial;

  /// The item's path on that device.
  final String relPath;

  /// The signed-in account, whose own ownership it can't change unless it is
  /// an admin.
  final String? selfUsername;

  /// Whether the signed-in account is an admin.
  final bool isAdmin;

  final LoadAccessFn _loadAccess;
  final LoadPrincipalsFn _loadPrincipals;
  final GrantAccessFn _grantAccess;
  final RevokeAccessFn _revokeAccess;

  PathAccess? _access;
  SharePrincipals _principals = const SharePrincipals();
  bool _isLoading = false;
  Object? _error;
  final Set<String> _busy = {};

  /// Bumped by every load and every answered change, so a slow load cannot
  /// overwrite a newer answer.
  int _generation = 0;
  bool _disposed = false;

  /// Whether the access has loaded.
  bool get hasLoaded => _access != null;

  /// Whether a load is in flight.
  bool get isLoading => _isLoading;

  /// Why the last load failed, or null. Raw; the host composes the copy.
  Object? get error => _error;

  /// Whether the signed-in account may change who has access.
  bool get canManage => _access?.canManage ?? false;

  /// Whether it may give the owner level.
  bool get canGrantOwner => _access?.canGrantOwner ?? false;

  /// Key suffixes of principals with a change in flight.
  Set<String> get busyKeys => Set.unmodifiable(_busy);

  /// Everyone with access, as the sheet shows them: access set on the item,
  /// then access inherited from the folders it is in.
  List<GrantItem> get grants {
    final access = _access;
    if (access == null) return const [];
    return [
      for (final grant in access.grants)
        GrantItem(
          principal: principalFor(grant),
          level: levelFor(grant.level),
          inheritedFrom: grant.from == access.relPath
              ? null
              : folderName(grant.from),
        ),
    ];
  }

  /// Everyone the item can be shared with: groups, `everyone` first, then
  /// accounts.
  List<PrincipalItem> get principals => [
    for (final group in _principals.groups)
      PrincipalItem(
        kind: PrincipalKind.group,
        id: group.id,
        name: group.name,
        isBuiltin: group.builtin,
      ),
    for (final user in _principals.users)
      PrincipalItem(kind: PrincipalKind.user, id: user.id, name: user.username),
  ];

  /// Rows the signed-in account can't change: its own ownership set on the
  /// item, unless it is an admin. The Quark refuses that change, so no one
  /// locks themselves out by accident.
  Set<String> get lockedKeys {
    final access = _access;
    if (isAdmin || access == null) return const {};
    return {
      for (final grant in access.grants)
        if (grant.userId != null &&
            grant.name == selfUsername &&
            grant.from == access.relPath &&
            grant.level == AccessLevel.owner.name)
          principalFor(grant).keySuffix,
    };
  }

  /// The level set on the item itself for [principal], or null when its
  /// access, if any, is only inherited.
  AccessLevel? directLevel(PrincipalItem principal) {
    for (final grant in grants) {
      if (!grant.isInherited &&
          grant.principal.kind == principal.kind &&
          grant.principal.id == principal.id) {
        return grant.level;
      }
    }
    return null;
  }

  /// The package's view of who [grant] is for.
  static PrincipalItem principalFor(PathGrant grant) {
    final groupId = grant.groupId;
    return groupId != null
        ? PrincipalItem(
            kind: PrincipalKind.group,
            id: groupId,
            name: grant.name,
            isBuiltin: grant.builtin,
          )
        : PrincipalItem(
            kind: PrincipalKind.user,
            id: grant.userId ?? 0,
            name: grant.name,
          );
  }

  /// The level the Quark calls [level]. An unknown one reads as view only.
  static AccessLevel levelFor(String level) {
    for (final value in AccessLevel.values) {
      if (value.name == level) return value;
    }
    return AccessLevel.read;
  }

  /// What a "From" line calls the folder at [path]: its own name, or `/` for
  /// the top of the device, as the file browser's breadcrumb does.
  static String folderName(String path) {
    final segments = [
      for (final segment in path.split('/'))
        if (segment.isNotEmpty) segment,
    ];
    return segments.isEmpty ? '/' : segments.last;
  }

  /// Fetches the access and who the item can be shared with. A newer load, or
  /// a change the Quark answers, supersedes this one.
  Future<void> load() async {
    final generation = ++_generation;
    _isLoading = true;
    _notify();
    try {
      final results = await Future.wait<Object>([
        _loadAccess(deviceSerial: deviceSerial, relPath: relPath),
        _loadPrincipals(),
      ]);
      if (!_isCurrent(generation)) return;
      _access = results[0] as PathAccess;
      _principals = results[1] as SharePrincipals;
      _error = null;
    } catch (error) {
      if (!_isCurrent(generation)) return;
      _error = error;
    } finally {
      if (_isCurrent(generation)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Gives [principal] [level] access to the item, or changes the level it
  /// has. Null on success, otherwise the failure.
  Future<Object?> share(PrincipalItem principal, AccessLevel level) => _change(
    principal,
    () => _grantAccess(
      deviceSerial: deviceSerial,
      relPath: relPath,
      userId: _userId(principal),
      groupId: _groupId(principal),
      level: level.name,
    ),
  );

  /// Removes the access set on the item for [principal]. Null on success,
  /// otherwise the failure.
  Future<Object?> revoke(PrincipalItem principal) => _change(
    principal,
    () => _revokeAccess(
      deviceSerial: deviceSerial,
      relPath: relPath,
      userId: _userId(principal),
      groupId: _groupId(principal),
    ),
  );

  static int? _userId(PrincipalItem principal) =>
      principal.kind == PrincipalKind.user ? principal.id : null;

  static int? _groupId(PrincipalItem principal) =>
      principal.kind == PrincipalKind.group ? principal.id : null;

  /// Runs [request] for [principal], one change per principal at a time, and
  /// takes the Quark's answer as the new state.
  Future<Object?> _change(
    PrincipalItem principal,
    Future<PathAccess> Function() request,
  ) async {
    final key = principal.keySuffix;
    if (_busy.contains(key)) return null;
    _busy.add(key);
    _notify();
    try {
      final access = await request();
      if (!_disposed) {
        // The answer is the whole list, newer than any load still out.
        _generation++;
        _access = access;
        _error = null;
        _isLoading = false;
      }
      return null;
    } catch (error) {
      return error;
    } finally {
      _busy.remove(key);
      _notify();
    }
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
