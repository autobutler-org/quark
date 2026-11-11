import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/api_explorer_controller.dart';
import 'package:quark/models/api_endpoint.dart' as model;
import 'package:quark/pages/api_explorer_page.dart';
import 'package:quark/router.dart';
import 'package:quark/widgets/settings/settings_about_tab.dart';

import '../support/tap_target_guidelines.dart' show setViewport;

/// The API explorer (#4077): reached from Settings' About tab, and a request
/// that can change data is confirmed before it goes.
void main() {
  testWidgets('the About tab has a row that opens the explorer', (
    tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsAboutTab(
            appVersion: null,
            appReleaseUrl: null,
            onOpenReleaseNotes: (_) {},
            onOpenTerms: () {},
            onOpenApiExplorer: () => opened++,
            isLoadingSbom: false,
            sbomError: null,
            flutterSbom: const [],
            goSbom: null,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('settings_api_explorer')));

    expect(opened, 1);
  });

  testWidgets('the route opens the page on the generated registry', (
    tester,
  ) async {
    setViewport(tester, const Size(1280, 800));
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: AppRoutes.apiExplorer,
          routes: router.configuration.routes
              .whereType<GoRoute>()
              .where((route) => route.path == AppRoutes.apiExplorer)
              .toList(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ApiExplorerPage), findsOneWidget);
    expect(find.byKey(const ValueKey('api_search')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('api_endpoint_get_api_v0_access')),
      findsOneWidget,
    );
  });

  group('sending', () {
    final sent = <(String, Uri)>[];

    Future<void> pumpExpanded(WidgetTester tester, String id) async {
      sent.clear();
      setViewport(tester, const Size(1280, 2400));
      await tester.pumpWidget(
        MaterialApp(
          home: ApiExplorerPage(
            controller: ApiExplorerController(
              loadEndpoints: () async => const [
                model.ApiEndpoint(
                  method: 'DELETE',
                  path: '/api/v0/albums/{id}',
                  inSwagger: true,
                  tags: ['albums'],
                  parameters: [
                    model.ApiParameter(
                      name: 'id',
                      location: model.ApiParameterLocation.path,
                      required: true,
                    ),
                  ],
                ),
                model.ApiEndpoint(
                  method: 'GET',
                  path: '/api/v0/health',
                  inSwagger: true,
                  tags: ['health'],
                ),
              ],
              send: ({required method, required uri, body}) async {
                sent.add((method, uri));
                return (
                  statusCode: 204,
                  headers: const <String, String>{},
                  body: '',
                  truncated: false,
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('api_endpoint_$id')));
      await tester.pumpAndSettle();
    }

    testWidgets('a DELETE names its URL and sends nothing on cancel', (
      tester,
    ) async {
      await pumpExpanded(tester, 'delete_api_v0_albums_id');
      await tester.enterText(find.byKey(const ValueKey('api_param_id')), '7');
      await tester.tap(find.byKey(const ValueKey('api_send')));
      await tester.pumpAndSettle();

      expect(find.textContaining('DELETE '), findsWidgets);
      expect(find.textContaining('/api/v0/albums/7'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('api_confirm_cancel')));
      await tester.pumpAndSettle();
      expect(sent, isEmpty);

      await tester.tap(find.byKey(const ValueKey('api_send')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('api_confirm_confirm')));
      await tester.pumpAndSettle();
      expect(sent.single.$1, 'DELETE');
      expect(sent.single.$2.path, '/api/v0/albums/7');
      expect(find.byKey(const ValueKey('api_response_status')), findsOneWidget);
    });

    testWidgets('a GET goes without asking', (tester) async {
      await pumpExpanded(tester, 'get_api_v0_health');
      await tester.tap(find.byKey(const ValueKey('api_send')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('api_confirm_cancel')), findsNothing);
      expect(sent.single.$1, 'GET');
    });
  });
}
