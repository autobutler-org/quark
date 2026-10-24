import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show ClientException;
import 'package:quark/models/thumbnail_probe.dart';
import 'package:quark/services/thumbnail_backfill.dart';
import 'package:quark/services/thumbnail_cache_manager.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/photos/photo_thumbnail.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../support/fake_thumbnail_store.dart';

/// A thumbnail endpoint that always gives the same answer: a status, or a 200
/// with [body].
FakeThumbnailStore _endpoint(int status, {Uint8List? body}) =>
    FakeThumbnailStore((url) {
      if (status != 200) {
        throw HttpExceptionWithStatus(status, 'scripted', uri: Uri.parse(url));
      }
      return body!;
    });

Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
}

Widget _tile(PhotoThumbnail thumbnail) => MaterialApp(
  home: Center(child: SizedBox.square(dimension: 120, child: thumbnail)),
);

/// The state a settled tile shows: the issue its key names, or null while it
/// is only a placeholder.
ThumbnailIssue? _shownIssue() {
  for (final issue in ThumbnailIssue.values) {
    if (find
        .byKey(ValueKey('photo_thumbnail_${issue.name}'))
        .evaluate()
        .isNotEmpty) {
      return issue;
    }
  }
  return null;
}

void main() {
  tearDown(() {
    imageCache
      ..clear()
      ..clearLiveImages();
  });

  /// #3509: a gone thumbnail, a corrupt one and one the Quark would not send
  /// all drew the same anonymous gray box.
  for (final (label, endpoint, issue) in [
    ('a 404', () => _endpoint(404), ThumbnailIssue.missing),
    ('a 410', () => _endpoint(410), ThumbnailIssue.missing),
    (
      'a 200 that is not an image',
      () => _endpoint(200, body: Uint8List.fromList([0, 1, 2, 3])),
      ThumbnailIssue.unreadable,
    ),
    ('a 500', () => _endpoint(500), ThumbnailIssue.loadFailed),
  ]) {
    testWidgets('$label settles to the ${issue.name} state', (tester) async {
      final handle = tester.ensureSemantics();
      ThumbnailCacheManager.instance = endpoint();
      await tester.pumpWidget(
        _tile(
          PhotoThumbnail(
            url: Uri.parse('https://quark.test/t/beach.jpg'),
            path: 'photos/beach.jpg',
          ),
        ),
      );
      await _flush(tester);

      expect(_shownIssue(), issue);
      expect(
        find.bySemanticsLabel(
          Errors.thumbnailUnavailable(issue, isVideo: false),
        ),
        findsOneWidget,
      );
      expect(find.byType(RawImage), findsNothing);
      handle.dispose();
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }

  test('a failed request is not mistaken for a damaged file', () {
    expect(
      PhotoThumbnail.issueFor(ClientException('connection reset')),
      ThumbnailIssue.loadFailed,
    );
    expect(
      PhotoThumbnail.issueFor(Exception('Invalid image data')),
      ThumbnailIssue.unreadable,
    );
  });

  testWidgets('a tile with no path to backfill still says why', (tester) async {
    ThumbnailCacheManager.instance = _endpoint(404);
    await tester.pumpWidget(
      _tile(PhotoThumbnail(url: Uri.parse('https://quark.test/t/a.jpg'))),
    );
    await _flush(tester);

    expect(_shownIssue(), ThumbnailIssue.missing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a photo still being backfilled is not called missing', (
    tester,
  ) async {
    final gate = Completer<void>();
    ThumbnailCacheManager.instance = _endpoint(404);
    await tester.pumpWidget(
      _tile(
        PhotoThumbnail(
          url: Uri.parse('https://quark.test/t/a.heic'),
          path: 'photos/a.heic',
          backfill: ThumbnailBackfill(
            probe: (path, {serial}) async {
              await gate.future;
              return const ThumbnailProbe(served: false, clientRender: false);
            },
          ),
        ),
      ),
    );
    await _flush(tester);
    expect(_shownIssue(), isNull, reason: 'the backfill has not answered');

    gate.complete();
    await _flush(tester);
    expect(_shownIssue(), ThumbnailIssue.missing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a photo the backfill could not read says so', (tester) async {
    ThumbnailCacheManager.instance = _endpoint(404);
    await tester.pumpWidget(
      _tile(
        PhotoThumbnail(
          url: Uri.parse('https://quark.test/t/b.heic'),
          path: 'photos/b.heic',
          backfill: ThumbnailBackfill(
            probe: (path, {serial}) async => const ThumbnailProbe(
              served: false,
              clientRender: true,
              modTime: '1',
              reason: 'unreadable',
            ),
            downloadOriginal: (path, {serial}) async => Uint8List(0),
            renderFromBytes: (name, bytes) async => null,
          ),
        ),
      ),
    );
    await _flush(tester);

    expect(_shownIssue(), ThumbnailIssue.unreadable);
    await tester.pumpWidget(const SizedBox());
  });
}
