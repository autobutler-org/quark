import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:quark/utils/app_log_config.dart';
import 'package:quark/utils/app_log_sink.dart';

/// The app log as a file under the app's support directory, on the client's
/// own disk: `logs/app.log`, with the file rotated out before it at
/// `logs/app.log.1`.
///
/// Every entry is flushed as it is written, so what was logged before a
/// crash is still there afterward. Calls are queued behind one another and
/// a failed one is dropped: logging never throws and never holds up a frame.
class IoAppLogSink implements AppLogSink {
  /// [root] is the directory the files live in and [maxFileBytes] the size
  /// that rotates the file out; a test passes a temporary directory and a
  /// small size.
  IoAppLogSink({
    Future<Directory> Function()? root,
    this.maxFileBytes = AppLogConfig.maxFileBytes,
  }) : _resolveRoot = root ?? _supportDirectory;

  /// How big the file grows before it is rotated out. A single entry larger
  /// than this still lands whole, in a file of its own.
  final int maxFileBytes;

  final Future<Directory> Function() _resolveRoot;

  /// Resolved once: the path does not move while the app runs. Null when it
  /// cannot be resolved, which leaves the sink keeping nothing.
  late final Future<Directory?> _root = Future.sync(_resolveRoot)
      .then<Directory?>(
        (root) => root,
        onError: (Object e) {
          debugPrint('[app_log_sink_io.dart] no directory: $e');
          return null;
        },
      );

  /// The last call queued. Every call chains onto it.
  Future<void> _tail = Future.value();

  /// The current file's size, read from disk once and counted from there.
  int? _size;

  static Future<Directory> _supportDirectory() async => Directory(
    '${(await getApplicationSupportDirectory()).path}/'
    '${AppLogConfig.directoryName}',
  );

  Future<T> _queued<T>(Future<T> Function() call) {
    final result = _tail.then((_) => call());
    _tail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  @override
  bool get persists => true;

  @override
  void write(String entry) {
    _queued(() async {
      try {
        final root = await _root;
        if (root == null) return;
        final file = File('${root.path}/${AppLogConfig.fileName}');
        final bytes = utf8.encode(entry);
        var size = _size ??= await file.exists() ? await file.length() : 0;
        if (size > 0 && size + bytes.length > maxFileBytes) {
          // Replaces the file rotated out before this one.
          await file.rename('${file.path}.1');
          size = 0;
        }
        await root.create(recursive: true);
        await file.writeAsBytes(bytes, mode: FileMode.append, flush: true);
        _size = size + bytes.length;
      } catch (e) {
        // The size is unknown after a failure; ask the disk again next time.
        _size = null;
        debugPrint('[app_log_sink_io.dart] write failed: $e');
      }
    });
  }

  @override
  Future<String> read() => _queued(() async {
    try {
      final root = await _root;
      if (root == null) return '';
      final current = File('${root.path}/${AppLogConfig.fileName}');
      final parts = <String>[];
      for (final file in [File('${current.path}.1'), current]) {
        // A file cut mid-character by a crash must still read.
        if (await file.exists()) {
          parts.add(
            utf8.decode(await file.readAsBytes(), allowMalformed: true),
          );
        }
      }
      return parts.join();
    } catch (e) {
      debugPrint('[app_log_sink_io.dart] read failed: $e');
      return '';
    }
  });
}

/// The native sink.
final AppLogSink appLogSinkPlatform = IoAppLogSink();
