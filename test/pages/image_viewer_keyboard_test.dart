import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/pages/file_viewer_page.dart';
import 'package:quark/pages/image_viewer_page.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #3360: the viewer's shortcuts worked when it was opened from the grid but
/// not from a search result, where Esc and f did nothing until the user
/// clicked the photo. On the web the search field is a DOM input; when the
/// viewer's route takes the focus that input closes, the browser's focus
/// falls to the page body, and the engine reports the Flutter view unfocused.
/// The framework answers by parking focus on the root scope, out of the
/// viewer, so no key reached it. The viewer takes the focus back once its
/// route has finished coming in.
void main() {
  // 64x64 solid PNG — the viewer needs bytes it can actually decode.
  final bytes = Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAAAT0lEQVR42u3P'
      'QQkAAAgEsIttCIMZywi+hcEKLNXzWgQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE'
      'BAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQELgvWNcGlSbHPawAAAABJRU5ErkJg'
      'gg==',
    ),
  );

  late List<String> favoriteRequests;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    favoriteRequests = [];
    resetSharedHttpClient();
    sharedHttpClientFactory = () => MockClient((request) async {
      switch (request.url.path) {
        case '/api/v0/photos/favorite':
          favoriteRequests.add(request.body);
          return http.Response('{"isFavorite": true}', 200);
        case '/api/v0/photos/metadata':
          return http.Response('{}', 404);
      }
      return http.Response.bytes(bytes, 200);
    });
  });

  tearDown(() {
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  /// Lets the photo decode, which takes real async, then settles.
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
    });
    await tester.pumpAndSettle();
  }

  /// A grid page whose tile pushes the viewer the way Photos does. With
  /// [withSearch] a focused search field sits above it, as it does while a
  /// search is open.
  Future<List<int>> openFromPhotos(
    WidgetTester tester, {
    required bool withSearch,
  }) async {
    final requested = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                if (withSearch)
                  const TextField(
                    key: ValueKey('search_field'),
                    autofocus: true,
                  ),
                InkWell(
                  key: const ValueKey('tile'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<bool>(
                      builder: (_) => ImageViewerPage(
                        bytes: bytes,
                        name: 'b.jpg',
                        relPath: 'photos/b.jpg',
                        initialIndex: 1,
                        imageCount: 3,
                        onLoadImage: (index) async {
                          requested.add(index);
                          return (
                            bytes,
                            'p$index.jpg',
                            'photos/p$index.jpg',
                            '',
                          );
                        },
                      ),
                    ),
                  ),
                  child: const SizedBox(width: 100, height: 100),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    if (withSearch) {
      await tester.enterText(find.byKey(const ValueKey('search_field')), 'b');
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasPrimaryFocus,
        isTrue,
      );
    }
    await tester.tap(find.byKey(const ValueKey('tile')));
    if (withSearch) {
      // What the web engine sends when the closed search input drops the
      // browser's focus, partway into the route's transition.
      await tester.pump(const Duration(milliseconds: 50));
      tester.binding.handleViewFocusChanged(
        ViewFocusEvent(
          viewId: tester.view.viewId,
          state: ViewFocusState.unfocused,
          direction: ViewFocusDirection.undefined,
        ),
      );
    }
    await settle(tester);
    return requested;
  }

  /// The viewer's own focus node: the one wrapping its Scaffold.
  FocusNode viewerFocus(WidgetTester tester) => tester
      .widget<Focus>(
        find
            .ancestor(
              of: find.byType(Scaffold).last,
              matching: find.byKey(const ValueKey('image_viewer_focus')),
            )
            .first,
      )
      .focusNode!;

  for (final withSearch in [false, true]) {
    final from = withSearch ? 'a search result' : 'the grid';

    group('opened from $from', () {
      testWidgets('the viewer holds primary focus', (tester) async {
        await openFromPhotos(tester, withSearch: withSearch);
        expect(viewerFocus(tester).hasPrimaryFocus, isTrue);
      });

      testWidgets('Escape closes it', (tester) async {
        await openFromPhotos(tester, withSearch: withSearch);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(ImageViewerPage), findsNothing);
      });

      testWidgets('f favorites the photo', (tester) async {
        await openFromPhotos(tester, withSearch: withSearch);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pumpAndSettle();
        expect(favoriteRequests, hasLength(1));
        expect(favoriteRequests.single, contains('photos/b.jpg'));
      });

      testWidgets('the arrow keys navigate', (tester) async {
        final requested = await openFromPhotos(tester, withSearch: withSearch);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await settle(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await settle(tester);
        expect(requested, [2, 1]);
      });
    });
  }

  // Files opens a photo at its own /view URL rather than pushing the viewer
  // over the browser. The folder listing fails here (every request answers
  // with the photo), so the arrows have nowhere to go, but Escape and f still
  // answer straight away.
  group('opened from Files', () {
    Future<GoRouter> openFromFiles(WidgetTester tester) async {
      final router = GoRouter(
        initialLocation: '/files',
        routes: [
          GoRoute(
            path: '/files',
            builder: (context, _) => Scaffold(
              body: TextButton(
                onPressed: () => context.go('/view/users/me/a.png'),
                child: const Text('open'),
              ),
            ),
            routes: [
              GoRoute(
                path: ':path(.*)',
                builder: (_, _) => const Scaffold(body: Text('folder')),
              ),
            ],
          ),
          GoRoute(
            path: '/view/:path(.*)',
            builder: (_, state) =>
                FileViewerPage(filePath: state.pathParameters['path']!),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pump();
      await tester.tap(find.text('open'));
      await settle(tester);
      return router;
    }

    testWidgets('the viewer holds primary focus', (tester) async {
      await openFromFiles(tester);
      expect(viewerFocus(tester).hasPrimaryFocus, isTrue);
    });

    testWidgets('Escape closes it to the folder', (tester) async {
      await openFromFiles(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(ImageViewerPage), findsNothing);
      expect(find.text('folder'), findsOneWidget);
    });

    testWidgets('f favorites the photo', (tester) async {
      await openFromFiles(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(favoriteRequests, hasLength(1));
      expect(favoriteRequests.single, contains('users/me/a.png'));
    });
  });
}
