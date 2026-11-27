import 'package:quark/models/photo_album.dart';

/// An album kept on this phone for offline viewing (#4222): which Quark and
/// account it belongs to, what the person chose to keep, and the listing and
/// size its last sync left.
///
/// Immutable; a sync answers with a [copyWith] of the one it started from.
class KeptAlbum {
  /// Creates a kept album.
  const KeptAlbum({
    required this.albumId,
    required this.name,
    required this.host,
    required this.account,
    this.originals = false,
    this.allowMobileData = false,
    this.items = const [],
    this.keptBytes = 0,
    this.complete = false,
  });

  /// The album on the Quark.
  final int albumId;

  /// The album's name when it was last synced, shown in Settings and in the
  /// album list with no network.
  final String name;

  /// The Quark the album lives on, as `AppSettings.activeHost` names it.
  final String host;

  /// The account the album was kept for.
  final String account;

  /// Whether the full originals are kept as well as the previews.
  final bool originals;

  /// Whether the album may download over mobile data, not only Wi-Fi.
  final bool allowMobileData;

  /// The album's photos as its last sync listed them: what the phone keeps,
  /// and what the album shows with no network.
  final List<PhotoAlbumItem> items;

  /// How many bytes the album's kept photos take on this phone.
  final int keptBytes;

  /// Whether every photo in [items] is on the phone.
  final bool complete;

  /// Whether this album belongs to [host] and [account].
  bool belongsTo(String? host, String? account) =>
      this.host == host && this.account == account;

  /// A copy with the given fields replaced.
  KeptAlbum copyWith({
    String? name,
    List<PhotoAlbumItem>? items,
    int? keptBytes,
    bool? complete,
  }) => KeptAlbum(
    albumId: albumId,
    name: name ?? this.name,
    host: host,
    account: account,
    originals: originals,
    allowMobileData: allowMobileData,
    items: items ?? this.items,
    keptBytes: keptBytes ?? this.keptBytes,
    complete: complete ?? this.complete,
  );

  /// Reads what [toJson] wrote.
  factory KeptAlbum.fromJson(Map<String, dynamic> json) => KeptAlbum(
    albumId: json['albumId'] as int,
    name: json['name'] as String,
    host: json['host'] as String,
    account: json['account'] as String,
    originals: json['originals'] as bool? ?? false,
    allowMobileData: json['allowMobileData'] as bool? ?? false,
    items: [
      for (final item in json['items'] as List<dynamic>? ?? const [])
        PhotoAlbumItem.fromJson(item as Map<String, dynamic>),
    ],
    keptBytes: json['keptBytes'] as int? ?? 0,
    complete: json['complete'] as bool? ?? false,
  );

  /// The album as [KeptAlbum.fromJson] reads it.
  Map<String, dynamic> toJson() => {
    'albumId': albumId,
    'name': name,
    'host': host,
    'account': account,
    'originals': originals,
    'allowMobileData': allowMobileData,
    'items': [for (final item in items) item.toJson()],
    'keptBytes': keptBytes,
    'complete': complete,
  };
}
