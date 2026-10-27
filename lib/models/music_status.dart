/// The music library's state, from `GET /api/v0/music/status`: how many
/// tracks the user can see and whether a scan is running, so an empty page
/// can say "scanning" rather than "no music".
class MusicStatus {
  /// Creates a status.
  const MusicStatus({this.trackCount = 0, this.lastScanAt, this.scanJobId});

  /// How many tracks the signed-in user can read.
  final int trackCount;

  /// When the last full scan finished, or null before the first.
  final DateTime? lastScanAt;

  /// The running or queued rescan job, or null when none is.
  final int? scanJobId;

  /// Whether a rescan is queued or running.
  bool get isScanning => scanJobId != null;

  /// Reads the status from the API's JSON.
  factory MusicStatus.fromJson(Map<String, dynamic> json) => MusicStatus(
    trackCount: (json['trackCount'] as num?)?.toInt() ?? 0,
    lastScanAt: switch (json['lastScanAt']) {
      final String at => DateTime.tryParse(at),
      _ => null,
    },
    scanJobId: (json['scanJobId'] as num?)?.toInt(),
  );
}
