import 'package:material_ui/material_ui.dart';
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

  // #3611: a stored flag from before setup is not the switch. The card
  // offers setup, including when the payload still says enabled and
  // connected.
  testWidgets('a stale on flag with setup still to do shows set up', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.dark(themeColor: QuarkThemeColor.classic),
        home: Scaffold(
          body: SingleChildScrollView(
            child: RemoteAccessCard(
              status: const RemoteAccessStatus(
                enabled: true,
                connected: true,
                remoteUrl: 'http://100.64.0.7:80',
                needsSetup: true,
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

    expect(find.byKey(const ValueKey('remote_access_set_up')), findsOneWidget);
    expect(find.byKey(const ValueKey('remote_access_switch')), findsNothing);
    expect(find.byKey(const ValueKey('remote_access_status_on')), findsNothing);
  });
}
