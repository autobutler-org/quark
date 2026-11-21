/// The music library's state, as `GET /api/v0/music/status` answers it: how
/// many tracks the caller can read, and whether a scan is under way, so an
/// empty page can say "scanning" rather than "no music".
class MusicStatus {
  const MusicStatus({this.trackCount = 0, this.lastScanAt, this.scanJobId});

  /// Reads the status object.
  factory MusicStatus.fromJson(Map<String, dynamic> json) => MusicStatus(
    trackCount: (json['trackCount'] as num?)?.toInt() ?? 0,
    lastScanAt: DateTime.tryParse(json['lastScanAt']?.toString() ?? ''),
    scanJobId: (json['scanJobId'] as num?)?.toInt(),
  );

  /// How many tracks the caller can read.
  final int trackCount;

  /// When the newest finished scan completed, null when none is on record.
  final DateTime? lastScanAt;

  /// The scan pending or running now, null when there is none.
  final int? scanJobId;

  /// Whether a scan is pending or running.
  bool get isScanning => scanJobId != null;
}
