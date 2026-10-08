import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/services/remote_access_service.dart';
import 'package:quark/widgets/settings/help_support_card.dart';
import 'package:quark/widgets/settings/remote_access_card.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The Remote access card on Settings, Network (#2857).
void main() {
  const channel = MethodChannel('plugins.flutter.io/url_launcher');

  // Get help used to go to Settings, About, which has nothing on remote
  // access and takes the reader away from the failure they were reading
  // (#2902). It opens the support page in the browser instead.
  testWidgets('Get help opens the support page and stays put', (tester) async {
    final launched = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'launch') {
        launched.add((call.arguments as Map)['url'] as String);
      }
      return true;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.dark(themeColor: QuarkThemeColor.classic),
        home: Scaffold(
          body: SingleChildScrollView(
            child: RemoteAccessCard(
              status: const RemoteAccessStatus(
                enabled: true,
                error: 'tsnet: rejected',
              ),
              isLoading: false,
              isWorking: false,
              error: null,
              disconnected: false,
              isAdmin: true,
              onRetry: () {},
              onSetUp: () {},
              onTurnOff: () {},
              onTryAgain: () {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('remote_access_get_help')));
    await tester.pumpAndSettle();
    expect(launched, [HelpSupportCard.supportUrl]);
    expect(find.byType(RemoteAccessCard), findsOneWidget);
  });
}
