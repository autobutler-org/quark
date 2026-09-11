/// One item in a device's trash, as `GET /api/v0/trash` describes it.
class TrashItem {
  const TrashItem({
    required this.trashName,
    required this.name,
    required this.originalPath,
    required this.isDir,
    required this.size,
    required this.trashedAt,
    required this.expiresAt,
    this.deviceSerial = '',
    this.deviceName = '',
  });

  /// Addresses the item in restore and delete requests.
  final String trashName;

  /// The item's name before it was trashed.
  final String name;

  /// Where a restore puts the item back, relative to the device's files
  /// directory. Empty when the Quark no longer knows.
  final String originalPath;
  final bool isDir;
  final int size;
  final DateTime trashedAt;

  /// When the Quark's hourly purge deletes the item for good.
  final DateTime expiresAt;

  /// The device whose trash holds the item; empty for the internal disk. Not
  /// in the JSON — the listing is per device, so the caller stamps it.
  final String deviceSerial;
  final String deviceName;

  /// The folder the item was deleted from, as `/Documents`, or `/` for the
  /// top level. Null when the original location is unknown.
  String? get originalFolder {
    if (originalPath.isEmpty) return null;
    final slash = originalPath.lastIndexOf('/');
    return slash <= 0 ? '/' : '/${originalPath.substring(0, slash)}';
  }

  /// Whole days until the purge, rounded up, so an item with an hour left
  /// reads as one day rather than zero. Never negative.
  int daysLeft(DateTime now) => _daysLeft(expiresAt, now);

  factory TrashItem.fromJson(
    Map<String, dynamic> json, {
    String deviceSerial = '',
    String deviceName = '',
  }) {
    return TrashItem(
      trashName: json['trashName'] as String? ?? '',
      name: json['name'] as String? ?? '',
      originalPath: json['originalPath'] as String? ?? '',
      isDir: json['isDir'] as bool? ?? false,
      size: (json['size'] as num?)?.toInt() ?? 0,
      trashedAt: _parseTime(json['trashedAt']),
      expiresAt: _parseTime(json['expiresAt']),
      deviceSerial: deviceSerial,
      deviceName: deviceName,
    );
  }
}

/// One device's trash: its items and how long anything stays in it.
class TrashListing {
  const TrashListing({required this.retentionDays, required this.items});

  final int retentionDays;
  final List<TrashItem> items;
}

/// Addresses a trashed item, or something inside a trashed folder, in a
/// restore or delete request.
class TrashRef {
  const TrashRef(this.trashName, [this.path = '']);

  final String trashName;

  /// Relative to the trashed item, slash-separated; empty is the item itself.
  final String path;

  Map<String, String> toJson() => {'trashName': trashName, 'path': path};

  @override
  bool operator ==(Object other) =>
      other is TrashRef && other.trashName == trashName && other.path == path;

  @override
  int get hashCode => Object.hash(trashName, path);

  @override
  String toString() => path.isEmpty ? trashName : '$trashName/$path';
}

/// A folder being browsed in the trash: a trashed folder ([path] empty), or a
/// folder inside one, on the device with [serial] (empty for the internal
/// disk).
typedef TrashLocation = ({String serial, String trashName, String path});

/// One entry inside a trashed folder, as `GET /api/v0/trash/contents`
/// describes it.
class TrashContentsItem {
  const TrashContentsItem({
    required this.name,
    required this.path,
    required this.isDir,
    required this.size,
  });

  final String name;

  /// Relative to the trashed item; what a contents listing, a restore or a
  /// delete takes to address this entry.
  final String path;
  final bool isDir;
  final int size;

  factory TrashContentsItem.fromJson(Map<String, dynamic> json) =>
      TrashContentsItem(
        name: json['name'] as String? ?? '',
        path: json['path'] as String? ?? '',
        isDir: json['isDir'] as bool? ?? false,
        size: (json['size'] as num?)?.toInt() ?? 0,
      );
}

/// What a folder in the trash holds.
class TrashContents {
  const TrashContents({
    required this.items,
    required this.originalPath,
    required this.expiresAt,
  });

  final List<TrashContentsItem> items;

  /// Where the folder would be restored to, relative to the device's files
  /// directory. Empty when the Quark no longer knows.
  final String originalPath;

  /// When the purge deletes the trashed item the folder belongs to.
  final DateTime expiresAt;

  /// Whole days until the purge, rounded up. Never negative.
  int daysLeft(DateTime now) => _daysLeft(expiresAt, now);

  factory TrashContents.fromJson(Map<String, dynamic> json) => TrashContents(
    items: (json['items'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(TrashContentsItem.fromJson)
        .toList(growable: false),
    originalPath: json['originalPath'] as String? ?? '',
    expiresAt: _parseTime(json['expiresAt']),
  );
}

DateTime _parseTime(Object? value) =>
    DateTime.tryParse(value?.toString() ?? '') ??
    DateTime.fromMillisecondsSinceEpoch(0);

int _daysLeft(DateTime expiresAt, DateTime now) {
  final hours = expiresAt.difference(now).inHours;
  return hours <= 0 ? 0 : (hours / 24).ceil();
}
