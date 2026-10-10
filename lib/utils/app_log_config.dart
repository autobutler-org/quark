/// Bounds on the app log kept on the client's own disk (#1822).
abstract final class AppLogConfig {
  /// The folder under the app's support directory that holds the log.
  static const String directoryName = 'logs';

  /// The file being appended to. The one rotated out sits beside it with a
  /// `.1` suffix, so the log never takes more than twice [maxFileBytes].
  static const String fileName = 'app.log';

  /// How big [fileName] grows before it is rotated out.
  static const int maxFileBytes = 512 * 1024;

  /// The longest single entry, stack trace included. The rest is cut.
  static const int maxEntryChars = 8 * 1024;
}
