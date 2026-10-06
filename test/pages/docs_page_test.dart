import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:go_router/go_router.dart';
import 'package:http/testing.dart';
import 'package:quark/controllers/file_type_listing_cache.dart';
import 'package:quark/pages/docs_page.dart';
import 'package:quark/router.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/widgets/docs/docs_body.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #1780: every visit to Docs started from an empty list and a spinner while
/// the Quark walked its whole tree again.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Holds the Quark's answers back while set. Made inside a test, never in
  /// setUp: a future completed outside the test's fake-async zone resumes on
  /// the real event loop, which pumpAndSettle never runs.
  Completer<void>? gate;
  late String docName;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FileTypeListingCache.instance.clear();
    gate = null;
    docName = 'budget';
    resetSharedHttpClient();
    sharedHttpClientFactory = () => MockClient((request) async {
      await gate?.future;
      if (request.url.path != '/api/v0/files/by-type') {
        return http.Response('[]', 200);
      }
      final type = request.url.queryParameters['fileType'];
      return http.Response(
        jsonEncode([
          {
            'name': '$docName.$type',
            'size': 1,
            'isDir': false,
            'dirPath': '$docName.$type',
            'fileType': type,
          },
        ]),
        200,
      );
    });
  });

  tearDown(() {
    FileTypeListingCache.instance.clear();
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  // The app bar's refresh button spins too; only the body's loader means the
  // list is not there.
  final bodyLoader = find.descendant(
    of: find.byType(DocsBody),
    matching: find.byType(QuarkLoader),
  );

  Future<void> visitDocs(WidgetTester tester) {
    final router = GoRouter(
      initialLocation: AppRoutes.docs,
      routes: [
        GoRoute(path: AppRoutes.docs, builder: (_, _) => const DocsPage()),
      ],
    );
    addTearDown(router.dispose);
    return tester.pumpWidget(MaterialApp.router(routerConfig: router));
  }

  testWidgets('a second visit shows the last list on its first frame', (
    tester,
  ) async {
    await visitDocs(tester);
    await tester.pumpAndSettle();
    expect(find.text('budget'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    gate = Completer<void>();
    docName = 'travel';
    await visitDocs(tester);

    expect(find.text('budget'), findsOneWidget);
    expect(bodyLoader, findsNothing);

    // The refresh still runs and replaces it.
    gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('travel'), findsOneWidget);
    expect(find.text('budget'), findsNothing);
  });

  testWidgets('a first visit with nothing cached still shows the loader', (
    tester,
  ) async {
    gate = Completer<void>();
    await visitDocs(tester);

    expect(bodyLoader, findsOneWidget);

    gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('budget'), findsOneWidget);
  });
}
