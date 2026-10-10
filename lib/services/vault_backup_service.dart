import 'dart:convert';

import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/vault_service.dart';
import 'package:quark/utils/error_text.dart';

/// What a restore from a backup drive did (#1665): how many entries and
/// folders it added, and how many it left alone because the vault already had
/// one with the same name.
class VaultRestoreResult {
  /// Entries added to the vault.
  final int entriesImported;

  /// Entries already in the vault, left unchanged.
  final int entriesSkipped;

  /// Folders added to the vault.
  final int foldersImported;

  /// Folders already in the vault, left unchanged.
  final int foldersSkipped;

  const VaultRestoreResult({
    this.entriesImported = 0,
    this.entriesSkipped = 0,
    this.foldersImported = 0,
    this.foldersSkipped = 0,
  });

  factory VaultRestoreResult.fromJson(Map<String, dynamic> json) =>
      VaultRestoreResult(
        entriesImported: json['entriesImported'] as int? ?? 0,
        entriesSkipped: json['entriesSkipped'] as int? ?? 0,
        foldersImported: json['foldersImported'] as int? ?? 0,
        foldersSkipped: json['foldersSkipped'] as int? ?? 0,
      );
}

/// Calls `POST /api/v0/vault/import-backup`: restores the vault backup a
/// snapshot backup left on a drive into the unlocked vault (#1665).
///
/// Not `/vault/import`, which reads an export file and lives on
/// [VaultService].
class VaultBackupService with AuthenticatedService {
  static final VaultBackupService _instance = VaultBackupService._();
  VaultBackupService._();
  static VaultBackupService get instance => _instance;

  /// Merges the backup on the drive with [deviceSerial] into the vault,
  /// opening it with [recoveryPassword].
  ///
  /// Throws [VaultLockedException] when the vault locked itself first, and an
  /// [ApiException] otherwise. The Quark's own error text is a diagnostic and
  /// is not read.
  static Future<VaultRestoreResult> restoreFromDrive({
    required String deviceSerial,
    required String recoveryPassword,
  }) async {
    final resp = await sharedHttpClient.post(
      apiBaseUri.resolve('/api/v0/vault/import-backup'),
      headers: {...instance.authHeaders, 'Content-Type': 'application/json'},
      body: json.encode({
        'deviceSerial': deviceSerial,
        'recoveryPassword': recoveryPassword,
      }),
    );
    if (resp.statusCode == 423) throw VaultLockedException();
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, 'Vault restore failed');
    }
    return VaultRestoreResult.fromJson(
      json.decode(resp.body) as Map<String, dynamic>,
    );
  }
}
