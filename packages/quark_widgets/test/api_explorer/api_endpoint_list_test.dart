/// `ApiEndpointList` lists an API's endpoints grouped by tag, marks the ones
/// that have no client caller or are missing from Swagger, and expands one
/// row to whatever the caller passes.
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

const _endpoints = [
  ApiEndpointItem(
    id: 'get_health',
    method: 'GET',
    path: '/api/v0/health',
    tag: 'health',
    summary: 'Report whether the server is up',
    callers: ['HealthService.getHealth'],
  ),
  ApiEndpointItem(
    id: 'post_users',
    method: 'POST',
    path: '/api/v0/users',
    tag: 'users',
  ),
  ApiEndpointItem(
    id: 'delete_trash',
    method: 'DELETE',
    path: '/api/v0/files/trash',
    tag: 'health',
    callers: ['TrashService.empty'],
    inSwagger: false,
  ),
];

void main() {
  ApiEndpointList list({
    List<ApiEndpointItem> endpoints = _endpoints,
    String? expandedId,
    Widget? expandedChild,
    List<String>? log,
  }) => ApiEndpointList(
    endpoints: endpoints,
    expandedId: expandedId,
    expandedChild: expandedChild,
    onSearchChanged: (text) => log?.add('search:$text'),
    onToggle: (id) => log?.add('toggle:$id'),
  );

  testBothViewports('groups the endpoints by tag in first-seen order', (
    tester,
    size,
  ) async {
    await pumpAt(tester, list(), size: size);

    expect(tester.takeException(), isNull);
    final health = tester.getTopLeft(
      find.byKey(const ValueKey('section_health')),
    );
    final users = tester.getTopLeft(
      find.byKey(const ValueKey('section_users')),
    );
    expect(health.dy, lessThan(users.dy));
    // The DELETE row sits in the health group, above the users group.
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('api_endpoint_delete_trash')))
          .dy,
      lessThan(users.dy),
    );
    for (final endpoint in _endpoints) {
      expect(
        find.byKey(ValueKey('api_endpoint_${endpoint.id}')),
        findsOneWidget,
      );
    }
  });

  testWidgets('marks no client caller and not in Swagger', (tester) async {
    await pumpAt(tester, list());

    // Only the POST row has no callers.
    expect(find.text('No client caller'), findsOneWidget);
    expect(find.text('Not in Swagger'), findsOneWidget);
    expect(find.text('Report whether the server is up'), findsOneWidget);
  });

  testWidgets('shows the empty copy when nothing matches', (tester) async {
    await pumpAt(tester, list(endpoints: const []));
    expect(find.text('No matching endpoints'), findsOneWidget);
    expect(find.byKey(const ValueKey('api_search')), findsOneWidget);
  });

  testWidgets('reports searches and row taps', (tester) async {
    final log = <String>[];
    await pumpAt(tester, list(log: log));

    await tester.enterText(find.byKey(const ValueKey('api_search')), 'users');
    await tester.tap(find.byKey(const ValueKey('api_endpoint_post_users')));
    await tester.pump();

    expect(log, ['search:users', 'toggle:post_users']);
  });

  testBothViewports('shows the expanded child under its row only', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      list(expandedId: 'post_users', expandedChild: const Text('details')),
      size: size,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('details'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('details')).dy,
      greaterThan(
        tester
            .getTopLeft(find.byKey(const ValueKey('api_endpoint_post_users')))
            .dy,
      ),
    );
  });

  testBothViewports('survives a long path and many endpoints', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      list(
        endpoints: [
          for (var i = 0; i < 100; i++)
            ApiEndpointItem(
              id: '$i',
              method: 'DELETE',
              path: '/api/v0/${'segment/' * 20}{id}',
              tag: 'tag ${i % 5}',
              summary: 'A summary long enough to wrap ' * 4,
              inSwagger: false,
            ),
        ],
      ),
      size: size,
    );
    expect(tester.takeException(), isNull);
  });

  for (final (label, brightness, tokens) in [
    ('dark', Brightness.dark, QuarkTokens.dark),
    ('light', Brightness.light, QuarkTokens.light),
  ]) {
    testWidgets('$label: the method badge takes its color from the tokens', (
      tester,
    ) async {
      await pumpAt(tester, list(), brightness: brightness);
      final badge = tester.widget<QuarkTintBadge>(
        find.widgetWithText(QuarkTintBadge, 'DELETE'),
      );
      expect(badge.color, tokens.error);
    });
  }

  testBothViewports('meets the tap target guidelines', (tester, size) async {
    await pumpAt(
      tester,
      Padding(padding: const EdgeInsets.all(16), child: list()),
      size: size,
    );
    await expectTapTargetGuidelines(tester);
  });
}
