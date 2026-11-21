/// One song in the Quark's music library: where its file is, and its title.
class MusicTrack {
  const MusicTrack({required this.relPath, this.serial = '', this.title = ''});

  /// Reads one entry of `GET /api/v0/music/tracks`' `tracks`.
  factory MusicTrack.fromJson(Map<String, dynamic> json) => MusicTrack(
    relPath: json['relPath']?.toString() ?? '',
    serial: json['serial']?.toString() ?? '',
    title: json['title']?.toString() ?? '',
  );

  /// The file's path within its device's files.
  final String relPath;

  /// The device holding the file, empty for the internal drive.
  final String serial;

  /// The tagged title, or the file name without its extension.
  final String title;
}
