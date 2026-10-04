import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/pages/vault_page.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/vault_service.dart';
import 'package:quark/widgets/vault/entry_detail_page.dart';
import 'package:quark/widgets/vault/entry_editor_page.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/text_scale.dart';

/// #2606, #2603, #2605: every state of the vault survives 200% text on a phone
/// and a desktop, and every control in it is labeled and big enough to hit.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void serve(Map<String, Object> status) {
    resetSharedHttpClient();
    sharedHttpClientFactory = () => MockClient((request) async {
      final Object? body = switch (request.url.path) {
        '/api/v0/vault/status' => status,
        '/api/v0/vault/entries' => {
          'entries': [
            {'id': 1, 'name': 'Bank of Somewhere', 'urlHost': 'bank.example'},
            {'id': 2, 'name': 'Mail', 'urlHost': 'mail.example'},
          ],
        },
        '/api/v0/vault/folders' => {
          'folders': [
            {'id': 1, 'name': 'Personal'},
          ],
        },
        _ => null,
      };
      return body == null
          ? http.Response('', 404)
          : http.Response(jsonEncode(body), 200);
    });
  }

  tearDown(() {
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  Future<void> pump(WidgetTester tester, Widget page) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
        home: page,
      ),
    );
    await tester.pumpAndSettle();
  }

  const states = {
    'setup': {'initialized': false, 'locked': true},
    'unlock': {
      'initialized': true,
      'locked': true,
      'lockReason': 'Locked after 5 minutes without use',
    },
    'disconnected': {
      'initialized': true,
      'locked': true,
      'deviceConnected': false,
    },
    'entry list': {'initialized': true, 'locked': false},
  };

  for (final MapEntry(key: name, value: status) in states.entries) {
    testLargeText('the $name view lays out and is accessible', (
      tester,
      _,
    ) async {
      serve(status);
      await pump(tester, const VaultPage());

      expect(tester.takeException(), isNull);
      await expectTapTargetGuidelines(tester);
    });
  }

  testLargeText('the error view lays out', (tester, _) async {
    resetSharedHttpClient();
    sharedHttpClientFactory = () =>
        MockClient((request) async => http.Response('', 500));
    await pump(tester, const VaultPage());

    expect(find.text('Retry'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectTapTargetGuidelines(tester);
  });

  const entry = VaultEntryDetail(
    id: 1,
    name: 'Bank of Somewhere',
    url: 'https://bank.example/login',
    urlHost: 'bank.example',
    username: 'ada@example.com',
    password: 'correct horse battery staple',
    notes: 'Security question: the name of the first cat.',
    totpSecret: 'JBSWY3DPEHPK3PXP',
    createdAt: '',
    updatedAt: '',
  );

  testLargeText('an entry lays out and its icon buttons are labeled', (
    tester,
    _,
  ) async {
    await pump(
      tester,
      EntryDetailPage(
        entry: entry,
        folders: const [],
        onSave: (_) async {},
        onDelete: () async {},
      ),
    );

    expect(find.byTooltip('Copy Username'), findsOneWidget);
    expect(find.byTooltip('Copy Password'), findsOneWidget);
    expect(find.byTooltip('Show password'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectTapTargetGuidelines(tester);

    await tester.tap(find.byTooltip('Show password'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Hide password'), findsOneWidget);
  });

  testLargeText('the new-entry form lays out', (tester, _) async {
    await pump(tester, const EntryEditorPage(folders: []));

    expect(tester.takeException(), isNull);
    await expectTapTargetGuidelines(tester);
  });
}
