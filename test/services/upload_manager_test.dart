import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:quark/models/upload_conflict.dart';
import 'package:quark/models/upload_session.dart';
import 'package:quark/services/resumable_upload_service.dart';
import 'package:quark/services/upload_chunk_source.dart';
import 'package:quark/services/upload_manager.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/upload_session_record.dart';
import 'package:quark/utils/upload_tree_utils.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// An upload must outlive the folder it was started from.
///
/// It used to run inside the file browser's State, so navigating away took the
/// progress with it, and every uploaded file published a server event that the
/// page turned into a full refresh — two extra requests per file, competing
/// with the uploads for the few connections a browser allows per host.
void main() {
  PendingUpload upload(String name, {String relativeDir = ''}) {
    return PendingUpload(
      relativeDir: relativeDir,
      name: name,
      build: () async =>
          http.MultipartFile.fromBytes('files', _bytes, filename: name),
    );
  }

  test('sends every queued file to its own directory', () async {
    final sent = <String>[];
    final manager = UploadManager.forTesting(
      sender:
          ({
            required currentPath,
            required selectedFiles,
            serial,
            conflict,
          }) async {
            sent.add('$currentPath/${selectedFiles.single.filename}');
          },
    );

    final done = manager.results.first;
    manager.enqueue(
      uploads: [
        upload('a.jpg', relativeDir: 'photos/2024'),
        upload('cover.png', relativeDir: 'photos'),
      ],
      uploadPath: '/vacation',
    );

    await done;

    expect(sent, ['/vacation/photos/2024/a.jpg', '/vacation/photos/cover.png']);
  });

  test('keeps running after every listener has gone away', () async {
    // The navigation case: the page that started the upload is disposed and
    // stops listening. The upload is not the page's to cancel.
    final completers = <Completer<void>>[];
    final manager = UploadManager.forTesting(
      sender:
          ({required currentPath, required selectedFiles, serial, conflict}) {
            final completer = Completer<void>();
            completers.add(completer);
            return completer.future;
          },
    );

    var notifications = 0;
    void listener() => notifications++;
    manager.addListener(listener);

    final done = manager.results.first;
    manager.enqueue(
      uploads: [upload('a.txt'), upload('b.txt'), upload('c.txt')],
      uploadPath: '/docs',
    );

    await pumpEventQueue();
    completers.first.complete();
    await pumpEventQueue();

    // Page disposed mid-upload.
    manager.removeListener(listener);
    final seenBeforeLeaving = notifications;

    // Drain the rest with nobody watching. The sender appends to `completers`
    // as each new file starts, so take a snapshot each pass rather than
    // iterating a list that is still growing.
    while (completers.length < 3 || completers.any((c) => !c.isCompleted)) {
      for (final completer in List.of(completers)) {
        if (!completer.isCompleted) completer.complete();
      }
      await pumpEventQueue();
    }

    final result = await done;

    expect(result.total, 3, reason: 'all three files were sent');
    expect(result.failed, 0);
    expect(completers, hasLength(3));
    expect(
      notifications,
      seenBeforeLeaving,
      reason: 'a detached page stops hearing, it does not stop the upload',
    );
  });

  test('reports progress as files complete', () async {
    final seen = <int>[];
    final manager = UploadManager.forTesting(
      sender:
          ({
            required currentPath,
            required selectedFiles,
            serial,
            conflict,
          }) async {},
    );
    manager.addListener(() {
      if (manager.isUploading) seen.add(manager.completed);
    });

    final done = manager.results.first;
    manager.enqueue(
      uploads: [upload('a.txt'), upload('b.txt')],
      uploadPath: '',
    );
    await done;

    expect(seen, containsAllInOrder([1, 2]));
  });

  test('extends the run instead of starting a second one', () async {
    final completers = <Completer<void>>[];
    final manager = UploadManager.forTesting(
      sender:
          ({required currentPath, required selectedFiles, serial, conflict}) {
            final completer = Completer<void>();
            completers.add(completer);
            return completer.future;
          },
    );

    final done = manager.results.first;
    manager.enqueue(uploads: [upload('a.txt')], uploadPath: '');
    await pumpEventQueue();
    manager.enqueue(uploads: [upload('b.txt')], uploadPath: '');

    expect(manager.total, 2, reason: 'one run covering both enqueues');

    while (completers.length < 2) {
      for (final c in completers) {
        if (!c.isCompleted) c.complete();
      }
      await pumpEventQueue();
    }
    for (final c in completers) {
      if (!c.isCompleted) c.complete();
    }

    final result = await done;
    expect(result.total, 2);
    expect(manager.isUploading, isFalse);
  });

  test(
    'a file that fails does not take the rest of the batch with it',
    () async {
      final sent = <String>[];
      final manager = UploadManager.forTesting(
        // One attempt each: retries are covered separately, and this is about
        // what happens to the other files when one is beyond saving.
        maxAttempts: 1,
        sender:
            ({
              required currentPath,
              required selectedFiles,
              serial,
              conflict,
            }) async {
              final name = selectedFiles.single.filename!;
              if (name == 'a.txt') throw Exception('network down');
              sent.add(name);
            },
      );

      final done = manager.results.first;
      manager.enqueue(
        uploads: [upload('a.txt'), upload('b.txt'), upload('c.txt')],
        uploadPath: '',
      );
      final result = await done;

      expect(sent, unorderedEquals(['b.txt', 'c.txt']));
      expect(result.failed, 1);
      expect(result.succeeded, 2);
    },
  );

  test('carries a cap note through to the end', () async {
    final manager = UploadManager.forTesting(
      sender:
          ({
            required currentPath,
            required selectedFiles,
            serial,
            conflict,
          }) async {},
    );

    final done = manager.results.first;
    manager.enqueue(
      uploads: [upload('a.txt')],
      uploadPath: '',
      note: 'Stopped at the first 2000 files',
    );
    final result = await done;

    // Reported once it is over, never as a prompt beforehand.
    expect(result.note, 'Stopped at the first 2000 files');
  });

  group('concurrency', () {
    test('sends several at once instead of one at a time', () async {
      var inFlight = 0;
      var peak = 0;
      final gate = Completer<void>();
      final manager = UploadManager.forTesting(
        concurrency: 3,
        sender:
            ({
              required currentPath,
              required selectedFiles,
              serial,
              conflict,
            }) async {
              inFlight++;
              peak = peak > inFlight ? peak : inFlight;
              await gate.future;
              inFlight--;
            },
      );

      final done = manager.results.first;
      manager.enqueue(
        uploads: List.generate(9, (i) => upload('f$i.txt')),
        uploadPath: '',
      );

      await pumpEventQueue();
      expect(peak, 3, reason: 'the whole pool is working, not one worker');

      gate.complete();
      final result = await done;
      expect(result.total, 9);
      expect(result.failed, 0);
    });

    test('never exceeds the pool size', () async {
      var inFlight = 0;
      var peak = 0;
      final gates = <Completer<void>>[];
      final manager = UploadManager.forTesting(
        concurrency: 2,
        sender:
            ({
              required currentPath,
              required selectedFiles,
              serial,
              conflict,
            }) async {
              inFlight++;
              peak = peak > inFlight ? peak : inFlight;
              final gate = Completer<void>();
              gates.add(gate);
              await gate.future;
              inFlight--;
            },
      );

      final done = manager.results.first;
      manager.enqueue(
        uploads: List.generate(8, (i) => upload('f$i.txt')),
        uploadPath: '',
      );

      // Release them a few at a time; the cap must hold throughout, not just
      // at the start.
      while (peak < 2 || gates.any((g) => !g.isCompleted)) {
        for (final gate in List.of(gates)) {
          if (!gate.isCompleted) gate.complete();
        }
        await pumpEventQueue();
      }

      final result = await done;
      expect(result.total, 8);
      expect(peak, lessThanOrEqualTo(2), reason: 'bounded, not unbounded');
      expect(gates, hasLength(8), reason: 'every file was still sent');
    });

    test('one slow file does not hold the pool behind it', () async {
      // The reason for a shared queue rather than fixed batches: a batch runs
      // at the speed of its slowest member.
      final slow = Completer<void>();
      final finished = <String>[];
      final manager = UploadManager.forTesting(
        concurrency: 2,
        sender:
            ({
              required currentPath,
              required selectedFiles,
              serial,
              conflict,
            }) async {
              final name = selectedFiles.single.filename!;
              if (name == 'slow.txt') {
                await slow.future;
              }
              finished.add(name);
            },
      );

      final done = manager.results.first;
      manager.enqueue(
        uploads: [
          upload('slow.txt'),
          upload('a.txt'),
          upload('b.txt'),
          upload('c.txt'),
        ],
        uploadPath: '',
      );

      await pumpEventQueue();
      expect(
        finished,
        containsAll(['a.txt', 'b.txt', 'c.txt']),
        reason: 'the other worker kept going past the stuck file',
      );

      slow.complete();
      final result = await done;
      expect(result.total, 4);
      expect(result.failed, 0);
    });

    test('a failure in one worker does not stop the others', () async {
      final manager = UploadManager.forTesting(
        concurrency: 3,
        sender:
            ({
              required currentPath,
              required selectedFiles,
              serial,
              conflict,
            }) async {
              if (selectedFiles.single.filename == 'bad.txt') {
                throw Exception('network down');
              }
            },
      );

      final done = manager.results.first;
      manager.enqueue(
        uploads: [
          upload('a.txt'),
          upload('bad.txt'),
          upload('b.txt'),
          upload('c.txt'),
        ],
        uploadPath: '',
      );
      final result = await done;

      expect(result.total, 4);
      expect(result.failed, 1);
      expect(result.succeeded, 3);
    });
  });

  group('failure path', () {
    test('retries a file before giving up on it', () async {
      var attempts = 0;
      final manager = UploadManager.forTesting(
        concurrency: 1,
        sender:
            ({
              required currentPath,
              required selectedFiles,
              serial,
              conflict,
            }) async {
              attempts++;
              if (attempts < 3) throw Exception('server busy');
            },
      );

      final done = manager.results.first;
      manager.enqueue(uploads: [upload('a.txt')], uploadPath: '');
      final result = await done;

      expect(attempts, 3, reason: 'a struggling server usually lands on retry');
      expect(result.failed, 0);
    });

    test(
      'a file that never responds fails instead of holding a worker',
      () async {
        // The Raspberry Pi case: the server accepts the request and then stops
        // answering. Nothing can abort the request, so the timeout is what frees
        // the worker — without it the batch never ends and the UI never unlocks.
        final manager = UploadManager.forTesting(
          concurrency: 1,
          attemptTimeout: const Duration(milliseconds: 50),
          maxAttempts: 1,
          sender:
              ({
                required currentPath,
                required selectedFiles,
                serial,
                conflict,
              }) => Completer<void>().future,
        );

        final done = manager.results.first;
        manager.enqueue(uploads: [upload('a.txt')], uploadPath: '');
        final result = await done;

        expect(result.failed, 1);
        expect(result.firstError, quarkDisconnectedInline);
        expect(manager.isUploading, isFalse, reason: 'the UI unlocks');
      },
    );

    test('gives up on the batch after enough failures in a row', () async {
      var sent = 0;
      final manager = UploadManager.forTesting(
        concurrency: 1,
        maxAttempts: 1,
        maxConsecutiveFailures: 3,
        sender:
            ({
              required currentPath,
              required selectedFiles,
              serial,
              conflict,
            }) async {
              sent++;
              throw Exception('disk full');
            },
      );

      final done = manager.results.first;
      manager.enqueue(
        uploads: List.generate(50, (i) => upload('f$i.txt')),
        uploadPath: '',
      );
      final result = await done;

      expect(sent, 3, reason: 'it stopped rather than grinding through 50');
      expect(result.stoppedEarly, isTrue);
      expect(result.total, 50);
      expect(result.completed, 3);
      expect(result.skipped, 47);
      expect(result.firstError, "Couldn't upload f0.txt.");
      expect(manager.isUploading, isFalse);
    });

    test('a success resets the run of failures', () async {
      var sent = 0;
      final manager = UploadManager.forTesting(
        concurrency: 1,
        maxAttempts: 1,
        maxConsecutiveFailures: 3,
        sender:
            ({
              required currentPath,
              required selectedFiles,
              serial,
              conflict,
            }) async {
              sent++;
              // Fail, fail, succeed, repeating: intermittent, not terminal.
              if (sent % 3 != 0) throw Exception('flaky');
            },
      );

      final done = manager.results.first;
      manager.enqueue(
        uploads: List.generate(9, (i) => upload('f$i.txt')),
        uploadPath: '',
      );
      final result = await done;

      expect(result.stoppedEarly, isFalse, reason: 'never 3 bad in a row');
      expect(result.completed, 9);
      expect(result.failed, 6);
    });

    test('cancel stops the queue and unlocks', () async {
      final gates = <Completer<void>>[];
      final manager = UploadManager.forTesting(
        concurrency: 1,
        sender:
            ({required currentPath, required selectedFiles, serial, conflict}) {
              final gate = Completer<void>();
              gates.add(gate);
              return gate.future;
            },
      );

      final done = manager.results.first;
      manager.enqueue(
        uploads: List.generate(20, (i) => upload('f$i.txt')),
        uploadPath: '',
      );
      await pumpEventQueue();

      manager.cancel();
      // The one in flight is not interrupted; it finishes and the run ends.
      for (final gate in List.of(gates)) {
        if (!gate.isCompleted) gate.complete();
      }
      final result = await done;

      expect(result.cancelled, isTrue);
      expect(result.completed, 1);
      expect(result.skipped, 19);
      expect(manager.isUploading, isFalse, reason: 'the UI unlocks');
    });

    test('cancel on an idle manager does nothing', () {
      final manager = UploadManager.forTesting(
        sender:
            ({
              required currentPath,
              required selectedFiles,
              serial,
              conflict,
            }) async {},
      );

      expect(manager.cancel, returnsNormally);
      expect(manager.isUploading, isFalse);
    });
  });

  /// A large file used to be read whole into the tab's memory and started again
  /// from zero on any interruption (#1629). Both are properties of what one
  /// worker does with one file; the pool above it is untouched.
  group('chunked uploads', () {
    late _FakeUploadServer server;
    late InMemoryUploadSessionStore store;
    late List<String> sentWhole;

    setUp(() {
      server = _FakeUploadServer();
      store = InMemoryUploadSessionStore();
      sentWhole = <String>[];
    });

    UploadManager managerFor({
      int chunkSizeBytes = 8,
      int chunkedThresholdBytes = 8,
      int concurrency = 1,
      int maxAttempts = kMaxUploadAttempts,
      int maxChunkAttempts = 3,
      int maxConsecutiveFailures = kMaxConsecutiveUploadFailures,
      Duration attemptTimeout = kUploadAttemptTimeout,
    }) {
      return UploadManager.forTesting(
        sender:
            ({
              required currentPath,
              required selectedFiles,
              serial,
              conflict,
            }) async {
              sentWhole.add(selectedFiles.single.filename!);
            },
        sessionClient: server,
        sessionStore: store,
        concurrency: concurrency,
        maxAttempts: maxAttempts,
        maxChunkAttempts: maxChunkAttempts,
        maxConsecutiveFailures: maxConsecutiveFailures,
        attemptTimeout: attemptTimeout,
        chunkSizeBytes: chunkSizeBytes,
        chunkedThresholdBytes: chunkedThresholdBytes,
        chunkRetryBackoff: Duration.zero,
      );
    }

    final modified = DateTime.utc(2026, 2, 3);

    PendingUpload sized(String name, int size, {String relativeDir = ''}) {
      return PendingUpload(
        relativeDir: relativeDir,
        name: name,
        build: () async =>
            http.MultipartFile.fromBytes('files', _bytes, filename: name),
        openChunkSource: () async =>
            _FakeChunkSource(size, lastModified: modified),
      );
    }

    String keyFor(String name, int size, {String rootDir = ''}) {
      return uploadFileIdentity(
        rootDir: rootDir,
        fileName: name,
        size: size,
        lastModified: modified,
      );
    }

    /// Every range the server was asked for, as `start-end` with an exclusive
    /// end — the form the client reasons in, before it becomes an inclusive
    /// Content-Range on the wire.
    void expectCovers(List<String> ranges, int total) {
      var expected = 0;
      for (final range in ranges) {
        final parts = range.split('-');
        expect(
          int.parse(parts[0]),
          expected,
          reason: 'chunk $range does not start where the last one ended',
        );
        expected = int.parse(parts[1]);
      }
      expect(expected, total, reason: 'the last chunk must reach the end');
    }

    test('a file below the threshold never opens a session', () async {
      // No regression in the common case: a photo is still one request, and
      // chunking it would only add a session round trip.
      final manager = managerFor(chunkedThresholdBytes: 16);

      final done = manager.results.first;
      manager.enqueue(uploads: [sized('small.bin', 15)], uploadPath: '/docs');
      final result = await done;

      expect(sentWhole, ['small.bin']);
      expect(server.created, isEmpty);
      expect(server.ranges, isEmpty);
      expect(result.failed, 0);
    });

    test('a file with no chunk source takes the whole-file path', () async {
      // What keeps every pre-#1629 caller working.
      final manager = managerFor();

      final done = manager.results.first;
      manager.enqueue(
        uploads: [
          PendingUpload(
            relativeDir: '',
            name: 'legacy.bin',
            build: () async => http.MultipartFile.fromBytes(
              'files',
              _bytes,
              filename: 'legacy.bin',
            ),
          ),
        ],
        uploadPath: '',
      );
      final result = await done;

      expect(sentWhole, ['legacy.bin']);
      expect(server.created, isEmpty);
      expect(result.failed, 0);
    });

    test(
      'chunks a file that does not divide evenly by the chunk size',
      () async {
        // The last partial chunk is where off-by-one lives.
        final manager = managerFor();

        final done = manager.results.first;
        manager.enqueue(uploads: [sized('big.bin', 20)], uploadPath: '');
        final result = await done;

        expect(server.ranges, ['0-8', '8-16', '16-20']);
        expectCovers(server.ranges, 20);
        expect(
          sentWhole,
          isEmpty,
          reason: 'no multipart request for a big file',
        );
        expect(result.failed, 0);
        expect(result.succeeded, 1);
      },
    );

    test('a file that is exactly one chunk is one request', () async {
      final manager = managerFor();

      final done = manager.results.first;
      manager.enqueue(uploads: [sized('exact.bin', 8)], uploadPath: '');
      await done;

      expect(server.ranges, ['0-8']);
      expectCovers(server.ranges, 8);
    });

    test('a chunk that fails resumes from the committed offset', () async {
      // Not from zero: the offset the server has already accepted is the whole
      // point of the protocol.
      server.intercept = (attempt, start, end) async {
        if (attempt == 2) {
          throw Exception('connection reset');
        }
        return null;
      };
      final manager = managerFor();

      final done = manager.results.first;
      manager.enqueue(uploads: [sized('big.bin', 20)], uploadPath: '');
      final result = await done;

      expect(server.ranges, ['0-8', '8-16', '8-16', '16-20']);
      expect(
        server.ranges.where((r) => r == '0-8'),
        hasLength(1),
        reason: 'the bytes already committed are never sent again',
      );
      expect(server.created, hasLength(1), reason: 'the session survived');
      expect(result.failed, 0);
    });

    test('a 409 carrying the real offset resyncs and finishes', () async {
      // The lost-response case: the server has the bytes, the client does not
      // know it. Resyncing costs a header; restarting would cost the file.
      server.intercept = (attempt, start, end) async {
        if (attempt == 1) {
          server.sessions[server.created.last]!.offset = 8;
          return const ChunkOffsetMismatch(offset: 8);
        }
        return null;
      };
      final manager = managerFor();

      final done = manager.results.first;
      manager.enqueue(uploads: [sized('big.bin', 20)], uploadPath: '');
      final result = await done;

      expect(server.ranges, ['0-8', '8-16', '16-20']);
      expect(server.created, hasLength(1), reason: 'resync, not restart');
      expect(result.failed, 0);
    });

    test('resumes a stored session from where the server got to', () async {
      final sessionId = server.seed(
        fileName: 'big.bin',
        totalSize: 20,
        offset: 8,
      );
      final key = keyFor('big.bin', 20);
      store.write(
        UploadSessionRecord(
          fileKey: key,
          sessionId: sessionId,
          offset: 8,
          totalSize: 20,
          fileName: 'big.bin',
          createdAt: DateTime.now(),
        ),
      );
      final manager = managerFor();

      final done = manager.results.first;
      manager.enqueue(uploads: [sized('big.bin', 20)], uploadPath: '');
      final result = await done;

      expect(server.created, isEmpty, reason: 'the stored session was reused');
      expect(server.ranges, ['8-16', '16-20']);
      expect(result.failed, 0);
      expect(store.read(key), isNull, reason: 'a finished file leaves nothing');
    });

    test(
      'a 404 on a resumed session discards the record and restarts',
      () async {
        final key = keyFor('big.bin', 20);
        store.write(
          UploadSessionRecord(
            fileKey: key,
            sessionId: 'ghost',
            offset: 8,
            totalSize: 20,
            fileName: 'big.bin',
            createdAt: DateTime.now(),
          ),
        );
        final manager = managerFor();

        final done = manager.results.first;
        manager.enqueue(uploads: [sized('big.bin', 20)], uploadPath: '');
        final result = await done;

        expect(
          server.created,
          hasLength(1),
          reason: 'a fresh session, not two',
        );
        expect(server.ranges, ['0-8', '8-16', '16-20']);
        expectCovers(server.ranges, 20);
        expect(result.failed, 0);
        expect(store.read(key), isNull);
      },
    );

    test('a stored record whose size disagrees is discarded', () async {
      // The identity is name, size and last-modified, which is weak on
      // purpose. This is the check that keeps the weakness from corrupting a
      // file: the server's own description of the session has to agree.
      final sessionId = server.seed(
        fileName: 'big.bin',
        totalSize: 999,
        offset: 8,
      );
      final key = keyFor('big.bin', 20);
      store.write(
        UploadSessionRecord(
          fileKey: key,
          sessionId: sessionId,
          offset: 8,
          totalSize: 20,
          fileName: 'big.bin',
          createdAt: DateTime.now(),
        ),
      );
      final manager = managerFor();

      final done = manager.results.first;
      manager.enqueue(uploads: [sized('big.bin', 20)], uploadPath: '');
      final result = await done;

      expect(server.created, hasLength(1));
      expect(server.ranges, ['0-8', '8-16', '16-20']);
      expect(result.failed, 0);
      expect(server.deleted, [
        sessionId,
      ], reason: 'the session we abandoned frees its temp file now');
    });

    test('a stored record whose name disagrees is discarded', () async {
      final sessionId = server.seed(
        fileName: 'other.bin',
        totalSize: 20,
        offset: 8,
      );
      final key = keyFor('big.bin', 20);
      store.write(
        UploadSessionRecord(
          fileKey: key,
          sessionId: sessionId,
          offset: 8,
          totalSize: 20,
          fileName: 'big.bin',
          createdAt: DateTime.now(),
        ),
      );
      final manager = managerFor();

      final done = manager.results.first;
      manager.enqueue(uploads: [sized('big.bin', 20)], uploadPath: '');
      await done;

      expect(server.created, hasLength(1));
      expect(server.ranges, ['0-8', '8-16', '16-20']);
    });

    test(
      'a session that cannot be checked is deleted before starting over',
      () async {
        final sessionId = server.seed(
          fileName: 'big.bin',
          totalSize: 20,
          offset: 8,
        );
        final key = keyFor('big.bin', 20);
        store.write(
          UploadSessionRecord(
            fileKey: key,
            sessionId: sessionId,
            offset: 8,
            totalSize: 20,
            fileName: 'big.bin',
            createdAt: DateTime.now(),
          ),
        );
        server.getSessionError = Exception('connection reset');
        final manager = managerFor();

        final done = manager.results.first;
        manager.enqueue(uploads: [sized('big.bin', 20)], uploadPath: '');
        final result = await done;

        expect(server.created, hasLength(1), reason: 'started over');
        expect(result.failed, 0);
        expect(server.deleted, [
          sessionId,
        ], reason: 'the session it replaced may still hold staged bytes');
      },
    );

    test('a stale record is pruned rather than resumed', () async {
      final sessionId = server.seed(
        fileName: 'big.bin',
        totalSize: 20,
        offset: 8,
      );
      final key = keyFor('big.bin', 20);
      store.write(
        UploadSessionRecord(
          fileKey: key,
          sessionId: sessionId,
          offset: 8,
          totalSize: 20,
          fileName: 'big.bin',
          createdAt: DateTime.now().subtract(const Duration(days: 3)),
        ),
      );
      final manager = managerFor();

      final done = manager.results.first;
      manager.enqueue(uploads: [sized('big.bin', 20)], uploadPath: '');
      await done;

      expect(server.created, hasLength(1), reason: 'started over');
      expect(server.ranges, ['0-8', '8-16', '16-20']);
    });

    test('a session that vanishes mid-file starts that file over', () async {
      // Sessions live in the server's memory, so a restart drops them. The
      // client cannot resume what is not there.
      server.intercept = (attempt, start, end) async {
        if (attempt == 2) {
          return const ChunkSessionGone();
        }
        return null;
      };
      final manager = managerFor();

      final done = manager.results.first;
      manager.enqueue(uploads: [sized('big.bin', 20)], uploadPath: '');
      final result = await done;

      expect(server.created, hasLength(2), reason: 'a second session');
      expect(server.ranges, ['0-8', '8-16', '0-8', '8-16', '16-20']);
      expect(result.failed, 0);
      expect(store.read(keyFor('big.bin', 20)), isNull);
    });

    test('cancel stops a chunked file on a chunk boundary', () async {
      // The one thing a whole-file upload could not do. Cancelling used to
      // mean waiting out however long the file in flight took, which for a
      // four-gigabyte file is the whole upload.
      late UploadManager manager;
      server.intercept = (attempt, start, end) async {
        if (attempt == 1) {
          manager.cancel();
        }
        return null;
      };
      manager = managerFor();

      final done = manager.results.first;
      manager.enqueue(uploads: [sized('big.bin', 40)], uploadPath: '');
      final result = await done;

      expect(server.ranges, ['0-8'], reason: 'it stopped at the boundary');
      expect(result.cancelled, isTrue);
      expect(result.completed, 0, reason: 'neither sent nor failed');
      expect(result.failed, 0);
      expect(
        server.deleted,
        server.created,
        reason: 'a canceled session frees its staged bytes now, not at expiry',
      );
      expect(store.read(keyFor('big.bin', 40)), isNull);
      expect(manager.isUploading, isFalse, reason: 'the UI unlocks');
    });

    test('giving up on a chunked file deletes its session', () async {
      server.intercept = (attempt, start, end) async {
        if (start == 8) {
          return const ChunkRejected(statusCode: 500, message: 'disk full');
        }
        return null;
      };
      final manager = managerFor(maxAttempts: 2);

      final done = manager.results.first;
      manager.enqueue(uploads: [sized('big.bin', 20)], uploadPath: '');
      final result = await done;

      expect(result.failed, 1);
      expect(server.created, hasLength(1), reason: 'the retry resumed it');
      expect(
        server.deleted,
        server.created,
        reason: 'nothing is left staged on the server once the client gives up',
      );
      expect(store.read(keyFor('big.bin', 20)), isNull);
    });

    test(
      'a resumed session holding every byte replays the last chunk to commit',
      () async {
        // A commit that failed (a full disk, say) leaves the session complete
        // but unwritten. Only a commit response means the file is in place.
        final sessionId = server.seed(
          fileName: 'big.bin',
          totalSize: 20,
          offset: 20,
        );
        final key = keyFor('big.bin', 20);
        store.write(
          UploadSessionRecord(
            fileKey: key,
            sessionId: sessionId,
            offset: 20,
            totalSize: 20,
            fileName: 'big.bin',
            createdAt: DateTime.now(),
          ),
        );
        final manager = managerFor();

        final done = manager.results.first;
        manager.enqueue(uploads: [sized('big.bin', 20)], uploadPath: '');
        final result = await done;

        expect(server.created, isEmpty);
        expect(server.ranges, ['12-20'], reason: 'the final chunk, replayed');
        expect(server.sessions, isEmpty, reason: 'the replay committed it');
        expect(result.failed, 0);
        expect(store.read(key), isNull);
      },
    );

    test(
      'a replayed final chunk that still fails to commit is not a success',
      () async {
        final sessionId = server.seed(
          fileName: 'big.bin',
          totalSize: 20,
          offset: 20,
        );
        final key = keyFor('big.bin', 20);
        store.write(
          UploadSessionRecord(
            fileKey: key,
            sessionId: sessionId,
            offset: 20,
            totalSize: 20,
            fileName: 'big.bin',
            createdAt: DateTime.now(),
          ),
        );
        server.intercept = (attempt, start, end) async =>
            const ChunkRejected(statusCode: 500, message: 'disk full');
        final manager = managerFor(maxAttempts: 1);

        final done = manager.results.first;
        manager.enqueue(uploads: [sized('big.bin', 20)], uploadPath: '');
        final result = await done;

        expect(server.ranges, ['12-20']);
        expect(result.failed, 1);
        expect(server.deleted, [sessionId]);
        expect(store.read(key), isNull);
      },
    );

    test('a rejected chunk fails the file, not the batch', () async {
      server.intercept = (attempt, start, end) async {
        if (start == 8) {
          return const ChunkRejected(statusCode: 400, message: 'bad range');
        }
        return null;
      };
      final manager = managerFor(maxAttempts: 1);

      final done = manager.results.first;
      manager.enqueue(
        uploads: [sized('big.bin', 20), sized('small.bin', 4)],
        uploadPath: '',
      );
      final result = await done;

      expect(result.failed, 1);
      expect(result.firstError, "Couldn't upload big.bin.");
      expect(sentWhole, ['small.bin'], reason: 'the other file still went');
    });

    test('gives up on the batch after enough chunked files fail', () async {
      server.intercept = (attempt, start, end) async =>
          const ChunkRejected(statusCode: 500, message: 'disk full');
      final manager = managerFor(maxAttempts: 1, maxConsecutiveFailures: 2);

      final done = manager.results.first;
      manager.enqueue(
        uploads: List.generate(6, (i) => sized('f$i.bin', 20)),
        uploadPath: '',
      );
      final result = await done;

      expect(result.stoppedEarly, isTrue);
      expect(result.failed, 2);
      expect(result.total, 6);
      expect(result.skipped, 4);
      expect(result.firstError, "Couldn't upload f0.bin.");
      expect(manager.isUploading, isFalse, reason: 'the UI unlocks');
    });

    test(
      'a chunk that never answers fails the file rather than the pool',
      () async {
        // The timeout bounds one chunk, not the whole file — a four-gigabyte
        // upload is minutes of honest work and must not trip it.
        server.intercept = (attempt, start, end) =>
            Completer<ChunkUploadOutcome?>().future;
        final manager = managerFor(
          maxAttempts: 1,
          maxChunkAttempts: 1,
          attemptTimeout: const Duration(milliseconds: 50),
        );

        final done = manager.results.first;
        manager.enqueue(uploads: [sized('big.bin', 20)], uploadPath: '');
        final result = await done;

        expect(result.failed, 1);
        expect(result.firstError, quarkDisconnectedInline);
        expect(manager.isUploading, isFalse);
      },
    );

    test('reports byte progress while a single file is in flight', () async {
      // completed counts whole files, which reads as no movement at all for as
      // long as one large file takes.
      final manager = managerFor();
      final seen = <int>[];
      manager.addListener(() {
        final progress = manager.chunkedProgress['/big.bin'];
        if (progress != null) seen.add(progress.sent);
      });

      final done = manager.results.first;
      manager.enqueue(uploads: [sized('big.bin', 20)], uploadPath: '');
      await done;

      expect(seen, containsAllInOrder([0, 8, 16, 20]));
      expect(manager.chunkedProgress, isEmpty, reason: 'cleared when done');
    });

    test('releases the chunk source however the file ends', () async {
      final sources = <_FakeChunkSource>[];
      server.intercept = (attempt, start, end) async =>
          const ChunkRejected(statusCode: 500, message: 'nope');
      final manager = UploadManager.forTesting(
        sender:
            ({
              required currentPath,
              required selectedFiles,
              serial,
              conflict,
            }) async {},
        sessionClient: server,
        sessionStore: store,
        concurrency: 1,
        maxAttempts: 1,
        chunkSizeBytes: 8,
        chunkedThresholdBytes: 8,
        chunkRetryBackoff: Duration.zero,
      );

      final done = manager.results.first;
      manager.enqueue(
        uploads: [
          PendingUpload(
            relativeDir: '',
            name: 'big.bin',
            build: () async => http.MultipartFile.fromBytes(
              'files',
              _bytes,
              filename: 'big.bin',
            ),
            openChunkSource: () async {
              final source = _FakeChunkSource(20);
              sources.add(source);
              return source;
            },
          ),
        ],
        uploadPath: '',
      );
      await done;

      expect(sources.single.released, isTrue);
    });

    test('sends the session to the directory the file belongs in', () async {
      final manager = managerFor();

      final done = manager.results.first;
      manager.enqueue(
        uploads: [sized('a.mp4', 20, relativeDir: 'photos/2024')],
        uploadPath: '/vacation',
      );
      await done;

      // Structure travels in rootDir, never in the filename (#1603).
      expect(server.createdRootDirs, ['vacation/photos/2024']);
      expect(server.createdFileNames, ['a.mp4']);
    });

    test('still runs four files at a time', () async {
      // #1629 changes what one worker does, not how many run.
      expect(kDefaultUploadConcurrency, 4);

      var inFlight = 0;
      var peak = 0;
      final gate = Completer<void>();
      server.intercept = (attempt, start, end) async {
        inFlight++;
        peak = peak > inFlight ? peak : inFlight;
        await gate.future;
        inFlight--;
        return null;
      };
      final manager = managerFor(concurrency: kDefaultUploadConcurrency);

      final done = manager.results.first;
      manager.enqueue(
        uploads: List.generate(9, (i) => sized('f$i.bin', 8)),
        uploadPath: '',
      );

      await pumpEventQueue();
      expect(peak, kDefaultUploadConcurrency);

      gate.complete();
      final result = await done;
      expect(result.total, 9);
      expect(result.failed, 0);
      expect(peak, lessThanOrEqualTo(kDefaultUploadConcurrency));
    });
  });
  group('a name the Quark already has', () {
    test('asks once and sends the answer with the file', () async {
      final conflicts = <UploadConflictChoice?>[];
      var refuse = true;
      final manager = UploadManager.forTesting(
        maxAttempts: 2,
        sender:
            ({
              required currentPath,
              required selectedFiles,
              serial,
              conflict,
            }) async {
              conflicts.add(conflict);
              if (conflict == null && refuse) {
                throw const ApiException(409, 'upload');
              }
            },
      );
      manager.conflictResolver = (fileName, {required offerApplyToAll}) async =>
          const UploadConflictAnswer(choice: UploadConflictChoice.keepBoth);

      manager.enqueue(uploads: [upload('a.txt')], uploadPath: '');
      final result = await manager.results.first;

      expect(conflicts, [null, UploadConflictChoice.keepBoth]);
      expect(result.succeeded, 1);
      expect(result.failed, 0);
      refuse = false;
    });

    test('a cancelled clash is not a failure', () async {
      final manager = UploadManager.forTesting(
        sender:
            ({
              required currentPath,
              required selectedFiles,
              serial,
              conflict,
            }) async {
              throw const ApiException(409, 'upload');
            },
      );
      manager.conflictResolver = (fileName, {required offerApplyToAll}) async =>
          const UploadConflictAnswer(choice: null);

      manager.enqueue(uploads: [upload('a.txt')], uploadPath: '');
      final result = await manager.results.first;

      expect(result.declined, 1);
      expect(result.failed, 0);
      expect(result.succeeded, 0);
    });

    test(
      'an answer that stands is asked for once and used for the rest',
      () async {
        var asked = 0;
        final manager = UploadManager.forTesting(
          concurrency: 1,
          sender:
              ({
                required currentPath,
                required selectedFiles,
                serial,
                conflict,
              }) async {
                if (conflict == null) {
                  throw const ApiException(409, 'upload');
                }
              },
        );
        manager.conflictResolver =
            (fileName, {required offerApplyToAll}) async {
              asked++;
              expect(offerApplyToAll, isTrue);
              return const UploadConflictAnswer(
                choice: UploadConflictChoice.replace,
                applyToAll: true,
              );
            };

        manager.enqueue(
          uploads: [upload('a.txt'), upload('b.txt'), upload('c.txt')],
          uploadPath: '',
        );
        final result = await manager.results.first;

        expect(asked, 1);
        expect(result.succeeded, 3);
      },
    );

    test('with nobody to ask, the file is reported as failed', () async {
      final manager = UploadManager.forTesting(
        sender:
            ({
              required currentPath,
              required selectedFiles,
              serial,
              conflict,
            }) async {
              throw const ApiException(409, 'upload');
            },
      );

      manager.enqueue(uploads: [upload('a.txt')], uploadPath: '');
      final result = await manager.results.first;

      expect(result.failed, 1);
      expect(result.firstError, Errors.fileNameTaken);
    });

    test('a chunked upload asks too, and reopens its session', () async {
      final server = _FakeUploadServer()..refuseUntilAnswered = true;
      final manager = UploadManager.forTesting(
        sender:
            ({
              required currentPath,
              required selectedFiles,
              serial,
              conflict,
            }) async {},
        sessionClient: server,
        sessionStore: InMemoryUploadSessionStore(),
        concurrency: 1,
        chunkSizeBytes: 8,
        chunkedThresholdBytes: 8,
        chunkRetryBackoff: Duration.zero,
      );
      manager.conflictResolver = (fileName, {required offerApplyToAll}) async =>
          const UploadConflictAnswer(choice: UploadConflictChoice.keepBoth);

      final done = manager.results.first;
      manager.enqueue(
        uploads: [
          PendingUpload(
            relativeDir: '',
            name: 'big.bin',
            build: () async => http.MultipartFile.fromBytes(
              'files',
              _bytes,
              filename: 'big.bin',
            ),
            openChunkSource: () async => _FakeChunkSource(20),
          ),
        ],
        uploadPath: '',
      );
      final result = await done;

      expect(server.createdConflicts, [null, UploadConflictChoice.keepBoth]);
      expect(result.succeeded, 1);
    });
  });
}

final _bytes = Uint8List.fromList([1, 2, 3]);

/// A chunk source that knows its size and nothing else.
///
/// The fake session client below never asks it for bytes: what these tests are
/// about is the loop over ranges and the retry accounting, and neither needs
/// real bytes to be wrong in an interesting way.
class _FakeChunkSource implements UploadChunkSource {
  _FakeChunkSource(this.size, {this.lastModified});

  @override
  final int size;

  @override
  final DateTime? lastModified;

  bool released = false;

  @override
  Future<http.Response> putRange({
    required Uri uri,
    required Map<String, String> headers,
    required int start,
    required int end,
  }) {
    throw UnsupportedError('the fake session client never sends bytes');
  }

  @override
  void release() => released = true;
}

class _FakeSession {
  _FakeSession({
    required this.rootDir,
    required this.fileName,
    required this.totalSize,
    this.offset = 0,
  });

  final String rootDir;
  final String fileName;
  final int totalSize;
  int offset;
}

/// The session half of the contract, in memory.
///
/// It enforces what the real server enforces — a chunk starts at the committed
/// offset, a replay below it is accepted and written nowhere, an unknown
/// session is gone — so a test that passes here is testing the protocol rather
/// than a mock's habits.
class _FakeUploadServer implements ResumableUploadClient {
  final Map<String, _FakeSession> sessions = {};
  final List<String> created = [];
  final List<String> createdRootDirs = [];
  final List<String> createdFileNames = [];
  final List<UploadConflictChoice?> createdConflicts = [];

  /// Stands in for a Quark whose name is taken: a session opened without a
  /// conflict choice is refused with a 409.
  bool refuseUntilAnswered = false;
  final List<String> deleted = [];
  final List<String> ranges = [];

  int puts = 0;
  int _counter = 0;

  /// Steps in before the server sees a chunk. Returning an outcome forces it;
  /// throwing stands in for a connection that dropped mid-request.
  Future<ChunkUploadOutcome?> Function(int attempt, int start, int end)?
  intercept;

  /// A session that already exists, as one left behind by an earlier page.
  String seed({
    required String fileName,
    required int totalSize,
    String rootDir = '',
    int offset = 0,
  }) {
    final sessionId = 'seeded-${++_counter}';
    sessions[sessionId] = _FakeSession(
      rootDir: rootDir,
      fileName: fileName,
      totalSize: totalSize,
      offset: offset,
    );
    return sessionId;
  }

  @override
  Future<UploadSession> createSession({
    required String rootDir,
    required String fileName,
    required int totalSize,
    String? serial,
    bool overwrite = false,
    UploadConflictChoice? conflict,
  }) async {
    createdConflicts.add(conflict);
    final refusal = refuseUntilAnswered && conflict == null
        ? const ApiException(409, 'open an upload session')
        : null;
    if (refusal != null) {
      throw refusal;
    }
    final sessionId = 'session-${++_counter}';
    sessions[sessionId] = _FakeSession(
      rootDir: rootDir,
      fileName: fileName,
      totalSize: totalSize,
    );
    created.add(sessionId);
    createdRootDirs.add(rootDir);
    createdFileNames.add(fileName);
    return UploadSession(sessionId: sessionId, offset: 0);
  }

  @override
  Future<ChunkUploadOutcome> putChunk({
    required String sessionId,
    required UploadChunkSource source,
    required int start,
    required int end,
    required int totalSize,
  }) async {
    puts++;
    ranges.add('$start-$end');
    final forced = await intercept?.call(puts, start, end);
    if (forced != null) {
      return forced;
    }

    final session = sessions[sessionId];
    if (session == null) {
      return const ChunkSessionGone();
    }
    if (end <= session.offset && session.offset < session.totalSize) {
      // Idempotent replay: a retry after a response lost in flight.
      return ChunkAccepted(offset: session.offset, complete: false);
    }
    // A replayed final chunk is written nowhere but reaches the commit again,
    // as on the real server.
    if (start != session.offset && end > session.offset) {
      return ChunkOffsetMismatch(offset: session.offset);
    }

    session.offset = math.max(session.offset, end);
    final complete = session.offset >= session.totalSize;
    if (complete) {
      sessions.remove(sessionId);
    }
    return ChunkAccepted(
      offset: session.offset,
      complete: complete,
      path: complete ? '${session.rootDir}/${session.fileName}' : null,
    );
  }

  /// Thrown from [getSession] when set, as a status check that never landed.
  Object? getSessionError;

  @override
  Future<UploadSessionStatus?> getSession(String sessionId) async {
    final error = getSessionError;
    if (error != null) {
      throw error;
    }
    final session = sessions[sessionId];
    if (session == null) {
      return null;
    }
    return UploadSessionStatus(
      sessionId: sessionId,
      offset: session.offset,
      totalSize: session.totalSize,
      fileName: session.fileName,
      rootDir: session.rootDir,
    );
  }

  @override
  Future<void> deleteSession(String sessionId) async {
    deleted.add(sessionId);
    sessions.remove(sessionId);
  }
}
