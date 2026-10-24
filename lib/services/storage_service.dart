import 'dart:convert';

import 'package:quark/services/app_settings.dart';
import 'package:quark/services/auth_secret.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';

// cspell:words reallocated celsius

/// Health the Quark reported for one drive on `GET /storage/devices/status`.
///
/// [verdict] is `healthy`, `watch`, `replace-soon`, or `unknown`. A missing
/// object is not this class: the caller treats that as Unknown. Detail fields
/// are null when the Quark omitted them. [speedClass] is `diskProbe.speedClass`,
/// copied here so the detail panel can show it beside the health readings.
/// [worseThanDefault] is the Quark's own comparison with the current default
/// storage drive.
class StorageDriveHealth {
  /// Creates a report with the raw [verdict] string.
  const StorageDriveHealth({
    required this.verdict,
    this.reason,
    this.smartStatus,
    this.reallocatedSectors,
    this.pendingSectors,
    this.powerOnHours,
    this.temperatureCelsius,
    this.media,
    this.linkSpeed,
    this.speedClass,
    this.worseThanDefault = false,
  });

  /// Parses `health`, plus [speedClass] from `diskProbe` when the caller has it.
  factory StorageDriveHealth.fromJson(
    Map<String, dynamic> json, {
    String? speedClass,
  }) {
    return StorageDriveHealth(
      verdict: json['verdict'] as String? ?? '',
      reason: json['reason'] as String?,
      smartStatus: json['smartStatus'] as String?,
      reallocatedSectors: _asInt(json['reallocatedSectors']),
      pendingSectors: _asInt(json['pendingSectors']),
      powerOnHours: _asInt(json['powerOnHours']),
      temperatureCelsius: _asInt(json['temperatureCelsius']),
      media: json['media'] as String?,
      linkSpeed: json['linkSpeed'] as String?,
      speedClass: speedClass,
      worseThanDefault: json['worseThanDefault'] as bool? ?? false,
    );
  }

  /// `healthy`, `watch`, `replace-soon`, `unknown`, or a word this app does not know.
  final String verdict;

  /// The Quark's one-sentence reason.
  final String? reason;

  /// Overall SMART status, such as `passed` or `failed`.
  final String? smartStatus;

  /// Reallocated sector count, when the Quark sent one.
  final int? reallocatedSectors;

  /// Pending sector count, when the Quark sent one.
  final int? pendingSectors;

  /// Power-on hours, when the Quark sent them.
  final int? powerOnHours;

  /// Temperature in Celsius, when the Quark sent it.
  final int? temperatureCelsius;

  /// `spinning` or `solid-state`, when the Quark sent it.
  final String? media;

  /// Link speed, in the Quark's words.
  final String? linkSpeed;

  /// `diskProbe.speedClass`: `fast`, `medium`, `slow`, or `unknown`.
  final String? speedClass;

  /// True when the Quark says this drive is worse than the current default storage.
  final bool worseThanDefault;
}

int? _asInt(Object? value) => value is num ? value.toInt() : null;

/// `health` on a device status, with `diskProbe.speedClass` attached.
///
/// Null only when the Quark sent neither. An empty verdict still comes back,
/// and the page shows that as Unknown.
StorageDriveHealth? _driveHealth(Map<String, dynamic> json) {
  final probe = json['diskProbe'];
  final speed = probe is Map ? probe['speedClass'] as String? : null;
  final raw = json['health'];
  if (raw is! Map) {
    if (speed == null || speed.isEmpty) return null;
    return StorageDriveHealth(verdict: '', speedClass: speed);
  }
  return StorageDriveHealth.fromJson(
    Map<String, dynamic>.from(raw),
    speedClass: speed,
  );
}

class StorageDevice {
  const StorageDevice({
    required this.name,
    required this.devicePath,
    required this.mountPoint,
    required this.fileSystem,
    required this.totalBytes,
    required this.usedBytes,
    required this.availableBytes,
    required this.isInternal,
    required this.isEnabled,
    this.model = '',
    this.serial = '',
    this.role = 'unassigned',
    this.categories = const {},
    this.health,
  });

  factory StorageDevice.fromJson(Map<String, dynamic> json) {
    // serial lives inside the nested usbInfo object
    final usbInfo = json['usbInfo'] as Map<String, dynamic>?;
    final serial = usbInfo?['serial'] as String? ?? '';

    final rawCats = json['categories'] as Map<String, dynamic>?;
    final categories = rawCats != null
        ? rawCats.map((k, v) => MapEntry(k, (v as num).toInt()))
        : const <String, int>{};

    return StorageDevice(
      name: json['name'] as String? ?? '',
      devicePath: json['devicePath'] as String? ?? '',
      mountPoint: json['mountPoint'] as String? ?? '',
      fileSystem: json['fileSystem'] as String? ?? '',
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      usedBytes: (json['usedBytes'] as num?)?.toInt() ?? 0,
      availableBytes: (json['availableBytes'] as num?)?.toInt() ?? 0,
      isInternal: json['isInternal'] as bool? ?? false,
      isEnabled: json['isEnabled'] as bool? ?? false,
      model: json['model'] as String? ?? '',
      serial: serial,
      role: json['role'] as String? ?? 'unassigned',
      categories: categories,
      health: _driveHealth(json),
    );
  }

  final String name;
  final String devicePath;
  final String mountPoint;
  final String fileSystem;
  final int totalBytes;
  final int usedBytes;
  final int availableBytes;
  final bool isInternal;
  final bool isEnabled;
  final String model;

  /// USB serial number; empty string for internal devices.
  final String serial;

  /// Device role: 'default-storage', 'snapshot-backup', or 'unassigned'.
  final String role;

  /// File category breakdown in bytes, e.g. {'documents': 1024, 'media': 2048}.
  final Map<String, int> categories;

  /// Health the Quark reported. Null when the status omitted it.
  final StorageDriveHealth? health;

  /// Whether this device is detected but not yet mounted.
  bool get isUnmounted => !isInternal && mountPoint.isEmpty;

  double get usedPercent => totalBytes > 0 ? usedBytes / totalBytes * 100 : 0;

  String get usedDisplay =>
      '${formatBytes(usedBytes)} / ${formatBytes(totalBytes)}';

  /// Formats [bytes] with the same 1024-based units Health and the Files
  /// footer use (B, KB, MB, GB, TB). An exact byte count has no decimal;
  /// every larger unit shows one. Decimal GB made the same disk look larger
  /// on Devices (#2011).
  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var i = 0;
    while (value >= 1024 && i < units.length - 1) {
      value /= 1024;
      i++;
    }
    final digits = i == 0 ? 0 : 1;
    return '${value.toStringAsFixed(digits)} ${units[i]}';
  }
}

/// Calls `/api/v0/storage`: the drives the Quark manages, mounting, renaming and assigning roles, and snapshot
/// backups. Device listings are cached briefly.
class StorageService with AuthenticatedService {
  static final StorageService _instance = StorageService._();
  StorageService._();
  static StorageService get instance => _instance;

  // A 10-second TTL prevents hammering the expensive /storage/devices/status
  // endpoint. Simultaneous callers share a single in-flight Future so only one
  // HTTP request is ever in flight at a time (#1022).
  static const _deviceCacheTtl = Duration(seconds: 10);
  static List<StorageDevice>? _cachedDevices;
  static DateTime? _cachedAt;
  static Future<List<StorageDevice>>? _inFlight;

  /// Invalidate the device cache immediately (e.g. after mount/rename).
  static void invalidateDeviceCache() {
    _cachedDevices = null;
    _cachedAt = null;
    _inFlight = null;
  }

  /// Returns all storage devices with their current status and display names.
  ///
  /// Results are cached for [_deviceCacheTtl]. Simultaneous callers share a
  /// single in-flight request so only one HTTP call is ever outstanding (#1022).
  static Future<List<StorageDevice>> listDevices() async {
    final now = DateTime.now();
    if (_cachedDevices != null &&
        _cachedAt != null &&
        now.difference(_cachedAt!) < _deviceCacheTtl) {
      return _cachedDevices!;
    }
    // Coalesce concurrent callers onto the same Future.
    _inFlight ??= _fetchDevices().then(
      (result) {
        _cachedDevices = result;
        _cachedAt = DateTime.now();
        _inFlight = null;
        return result;
      },
      onError: (Object e) {
        _inFlight = null;
        throw e;
      },
    );
    return _inFlight!;
  }

  static Future<List<StorageDevice>> _fetchDevices() async {
    final uri = apiBaseUri.resolve('/api/v0/storage/devices/status');
    final response = await instance.authenticatedGet(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Failed to list storage devices');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final devices = body['devices'];
    if (devices == null || devices is! List) return [];
    return devices
        .whereType<Map<String, dynamic>>()
        .map(StorageDevice.fromJson)
        .toList();
  }

  /// Mounts a USB device by serial. Requires the quark to be running as root.
  static Future<void> mountDevice(String serial) async {
    final uri = apiBaseUri.resolve('/api/v0/storage/devices/usb/$serial');
    final response = await instance.authenticatedPost(uri);
    throwUnlessOk(response, 'Mount failed');
    // Device state changed — invalidate the cache so the next listDevices()
    // returns fresh data.
    invalidateDeviceCache();
  }

  /// Unmounts a USB storage device so it can be removed safely.
  ///
  /// Not yet called from the UI — the eject action is part 2 of issue #1664.
  /// Do not delete as unused; the endpoint and this client are deliberate
  /// groundwork for safe eject.
  static Future<void> unmountDevice(String serial) async {
    final uri = apiBaseUri.resolve('/api/v0/storage/devices/usb/$serial');
    final response = await instance.authenticatedDelete(uri);
    throwUnlessOk(response, 'Unmount failed');
    invalidateDeviceCache();
  }

  static Future<void> setDeviceRole({
    required String serial,
    required String role,
    required String username,
    required String password,
    bool acknowledgeHealth = false,
  }) async {
    final uri = apiBaseUri.resolve('/api/v0/storage/devices/role');
    final secret = await AuthSecret.resolve(
      username: username,
      password: password,
      use: AuthSecretUse.reconfirm,
    );
    final response = await instance.authenticatedPut(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'serial': serial,
        'role': role,
        'username': username,
        'password': secret.authKey,
        if (acknowledgeHealth) 'acknowledgeHealth': true,
      }),
    );
    throwUnlessOk(response, 'Failed to set role');
    invalidateDeviceCache();
  }

  /// Starts a snapshot backup onto [targetDeviceSerial] and returns its job
  /// id. It sends no password: the chat and vault are backed up as ciphertext
  /// (#3460).
  static Future<String> startSnapshotBackup({
    required String targetDeviceSerial,
    bool acknowledgeHealth = false,
  }) async {
    final uri = apiBaseUri.resolve('/api/v0/storage/devices/snapshot-backup');
    final response = await instance.authenticatedPost(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'targetDeviceSerial': targetDeviceSerial,
        if (acknowledgeHealth) 'acknowledgeHealth': true,
      }),
    );
    throwUnlessOk(response, 'Failed to start backup');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['jobId'] as String;
  }

  static Future<BackupJobStatus> getSnapshotBackupStatus(String jobId) async {
    final uri = apiBaseUri.resolve(
      '/api/v0/storage/devices/snapshot-backup/status/$jobId',
    );
    final response = await instance.authenticatedGet(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'Failed to get backup status');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return BackupJobStatus.fromJson(data);
  }

  static Future<VerifyResult> verifySnapshotBackup({
    required String deviceSerial,
    bool full = false,
  }) async {
    final uri = apiBaseUri.resolve(
      '/api/v0/storage/devices/snapshot-backup/verify',
    );
    final response = await instance.authenticatedPost(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'deviceSerial': deviceSerial, 'full': full}),
    );
    throwUnlessOk(response, 'Verify failed');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return VerifyResult.fromJson(data);
  }
}

class BackupJobStatus {
  final String id;
  final String status;
  final double progress;
  final int totalFiles;
  final int filesCopied;
  final int filesSkipped;
  final int totalBytes;
  final int bytesCopied;
  final String? errorMsg;

  const BackupJobStatus({
    required this.id,
    required this.status,
    required this.progress,
    required this.totalFiles,
    required this.filesCopied,
    required this.filesSkipped,
    required this.totalBytes,
    required this.bytesCopied,
    this.errorMsg,
  });

  factory BackupJobStatus.fromJson(Map<String, dynamic> json) {
    return BackupJobStatus(
      id: json['id'] as String? ?? '',
      status: json['status'] as String? ?? '',
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
      totalFiles: (json['totalFiles'] as num?)?.toInt() ?? 0,
      filesCopied: (json['filesCopied'] as num?)?.toInt() ?? 0,
      filesSkipped: (json['filesSkipped'] as num?)?.toInt() ?? 0,
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      bytesCopied: (json['bytesCopied'] as num?)?.toInt() ?? 0,
      errorMsg: json['errorMsg'] as String?,
    );
  }

  bool get isRunning =>
      status == 'PENDING' || status == 'SCANNING' || status == 'COPYING';
  bool get isComplete => status == 'COMPLETED';
  bool get isFailed => status == 'FAILED';
}

class VerifyResult {
  final int ok;
  final List<String> missing;
  final List<String> corrupted;
  final List<String> added;

  const VerifyResult({
    required this.ok,
    this.missing = const [],
    this.corrupted = const [],
    this.added = const [],
  });

  factory VerifyResult.fromJson(Map<String, dynamic> json) {
    return VerifyResult(
      ok: (json['ok'] as num?)?.toInt() ?? 0,
      missing: (json['missing'] as List<dynamic>?)?.cast<String>() ?? [],
      corrupted: (json['corrupted'] as List<dynamic>?)?.cast<String>() ?? [],
      added: (json['added'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }

  bool get isHealthy => missing.isEmpty && corrupted.isEmpty;
}
