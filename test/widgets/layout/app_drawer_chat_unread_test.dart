import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/chat_unread_controller.dart';
import 'package:quark/models/chat_channel.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/widgets/layout/app_drawer.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../support/secure_storage.dart';
import '../../support/tap_target_guidelines.dart' show setViewport;

/// #2424: the drawer's Chat row carries a dot while any channel holds an
/// unread message, read as the drawer opens and cleared live.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final settings = AppSettings.instance;
  const dot = ValueKey('drawer_chat_unread');

  setUpAll(mockSecureStorage);

  tearDown(() => settings.featureFlags.value = const []);

  Future<void> pumpDrawer(
    WidgetTester tester,
    Size size,
    ChatUnreadController unread,
  ) async {
    setViewport(tester, size);
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
    // On a phone the household rows fill the screen before Chat's; the
    // drawer's list only builds the rows scrolled into view.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('drawer_chat')),
      50,
    );
  }

  for (final (label, size) in [
    ('narrow', const Size(360, 640)),
    ('wide', const Size(1280, 800)),
  ]) {
    testWidgets('dots the Chat row while a channel is unread, and clears '
        'it when another session reads it ($label)', (tester) async {
      final events = StreamController<FileEvent>.broadcast();
      addTearDown(events.close);
      final unread = ChatUnreadController(
        listChannels: () async => const [
          ChatChannel(id: 1, name: 'general'),
          ChatChannel(id: 4, name: 'family', unreadCount: 2),
        ],
        currentUserId: () => 7,
        events: events.stream,
      );
      addTearDown(unread.dispose);

      await pumpDrawer(tester, size, unread);

      expect(find.byKey(dot), findsOneWidget);
      expect(tester.takeException(), isNull);

      events.add(
        const FileEvent(
          kind: 'chat_read_marker_changed',
          path: '',
          data: {'channelId': 4, 'lastReadMessageId': 9, 'unreadCount': 0},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(dot), findsNothing);
    });
  }

  testWidgets('shows no dot with everything read', (tester) async {
    final unread = ChatUnreadController(
      listChannels: () async => const [ChatChannel(id: 1, name: 'general')],
      currentUserId: () => 7,
      events: const Stream.empty(),
    );
    addTearDown(unread.dispose);

    await pumpDrawer(tester, const Size(360, 640), unread);

    expect(find.byKey(const ValueKey('drawer_chat')), findsOneWidget);
    expect(find.byKey(dot), findsNothing);
  });

  testWidgets('loads unread counts with no feature flags', (tester) async {
    var lists = 0;
    final unread = ChatUnreadController(
      listChannels: () async {
        lists++;
        return const [ChatChannel(id: 4, name: 'family', unreadCount: 2)];
      },
      currentUserId: () => 7,
      events: const Stream.empty(),
    );
    addTearDown(unread.dispose);

    await pumpDrawer(tester, const Size(360, 640), unread);

    expect(lists, 1);
    expect(find.byKey(const ValueKey('drawer_chat')), findsOneWidget);
    expect(find.byKey(dot), findsOneWidget);
  });
}
