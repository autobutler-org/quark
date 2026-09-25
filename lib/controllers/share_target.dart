import 'package:quark/models/path_grant.dart';
import 'package:quark/services/sharing_service.dart';

typedef LoadAccessFn =
    Future<PathAccess> Function({
      required String deviceSerial,
      required String relPath,
    });
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

/// What the share sheet shares (#2422): a file or folder ([PathShareTarget]),
/// or a chat channel's members (`ChatChannelShareTarget`).
///
/// Everything the sheet knew about paths lives behind this. Each call answers
/// with the whole access list in [PathAccess]'s shape; a target with no
/// inheritance gives every grant a `from` equal to the access's `relPath`,
/// so nothing reads as inherited.
abstract class ShareTarget {
  /// Allows subclasses to be const.
  const ShareTarget();

  /// Who has access, and whether the signed-in account may change it.
  Future<PathAccess> load();

  /// Gives account [userId] or group [groupId] [level] (`read`, `write` or
  /// `owner`), or changes the level it has.
  Future<PathAccess> grant({int? userId, int? groupId, required String level});

  /// Removes the access set for account [userId] or group [groupId].
  Future<PathAccess> revoke({int? userId, int? groupId});

  /// Whether [grant]'s row is fixed, beyond the signed-in account's own
  /// ownership, which the sheet always locks. None by default.
  bool isLocked(PathGrant grant) => false;
}

/// Sharing the file or folder at [relPath] on the device [deviceSerial]
/// through `/api/v0/access` (#1911).
///
/// The calls default to [SharingService]; tests pass fakes.
class PathShareTarget extends ShareTarget {
  /// Shares [relPath] on [deviceSerial].
  const PathShareTarget({
    required this.deviceSerial,
    required this.relPath,
    LoadAccessFn loadAccess = SharingService.load,
    GrantAccessFn grantAccess = SharingService.grant,
    RevokeAccessFn revokeAccess = SharingService.revoke,
  }) : _loadAccess = loadAccess,
       _grantAccess = grantAccess,
       _revokeAccess = revokeAccess;

  /// The device the item is on.
  final String deviceSerial;

  /// The item's path on that device.
  final String relPath;

  final LoadAccessFn _loadAccess;
  final GrantAccessFn _grantAccess;
  final RevokeAccessFn _revokeAccess;

  @override
  Future<PathAccess> load() =>
      _loadAccess(deviceSerial: deviceSerial, relPath: relPath);

  @override
  Future<PathAccess> grant({
    int? userId,
    int? groupId,
    required String level,
  }) => _grantAccess(
    deviceSerial: deviceSerial,
    relPath: relPath,
    userId: userId,
    groupId: groupId,
    level: level,
  );

  @override
  Future<PathAccess> revoke({int? userId, int? groupId}) => _revokeAccess(
    deviceSerial: deviceSerial,
    relPath: relPath,
    userId: userId,
    groupId: groupId,
  );
}
