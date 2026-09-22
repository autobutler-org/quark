import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/pages/vault_page.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/widgets/vault/vault_setup_view.dart';
import 'package:quark/widgets/vault/vault_unlock_view.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// #2045: a vault that has never been set up offers the setup form, not the
/// unlock screen. Only a vault that exists and is locked asks for a password.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void serveStatus(Map<String, Object> status) {
    resetSharedHttpClient();
    sharedHttpClientFactory = () => MockClient(
      (request) async => request.url.path == '/api/v0/vault/status'
          ? http.Response(jsonEncode(status), 200)
          : http.Response('', 404),
    );
  }

  tearDown(() {
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  Future<void> pumpVault(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
        home: const VaultPage(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an uninitialized vault shows the setup form', (tester) async {
    serveStatus({'initialized': false, 'locked': true});
    await pumpVault(tester);

    expect(find.byType(VaultSetupView), findsOneWidget);
    expect(find.byType(VaultUnlockView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an initialized, locked vault shows the unlock screen', (
    tester,
  ) async {
    serveStatus({'initialized': true, 'locked': true});
    await pumpVault(tester);

    expect(find.byType(VaultUnlockView), findsOneWidget);
    expect(find.byType(VaultSetupView), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
