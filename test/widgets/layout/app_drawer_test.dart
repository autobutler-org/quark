import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/chat_unread_controller.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/widgets/layout/app_drawer.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../support/secure_storage.dart';
import '../../support/tap_target_guidelines.dart' show setViewport;

/// #4151: System's Health and Storage describe the device and offer a member
/// nothing to do, so the drawer offers System to admins only, the way it
/// offers Users.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final settings = AppSettings.instance;
  const system = ValueKey('drawer_system');
  const users = ValueKey('drawer_users');

  setUpAll(mockSecureStorage);

  tearDown(() => settings.isAdmin.value = false);

  Future<void> pumpDrawer(WidgetTester tester) async {
    final unread = ChatUnreadController(
      listChannels: () async => const [],
      events: const Stream.empty(),
    );
    addTearDown(unread.dispose);
    // Tall enough that every row is built, Manage's included.
    setViewport(tester, const Size(1280, 1600));
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
        home: Scaffold(
          body: AppDrawer(
            activeSection: QuarkDrawerSection.files,
            unread: unread,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('offers a member no System row', (tester) async {
    settings.isAdmin.value = false;

    await pumpDrawer(tester);

    expect(find.byKey(system), findsNothing);
    expect(find.byKey(users), findsNothing);
  });

  testWidgets('offers an admin the System row', (tester) async {
    settings.isAdmin.value = true;

    await pumpDrawer(tester);

    expect(find.byKey(system), findsOneWidget);
    expect(find.byKey(users), findsOneWidget);
  });
}
