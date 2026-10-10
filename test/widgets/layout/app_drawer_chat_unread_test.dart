import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/chat_unread_controller.dart';
import 'package:quark/models/chat_channel.dart';
import 'package:quark/models/feature_flag.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/widgets/layout/app_drawer.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// #2424: the drawer's Chat row carries a dot while any channel holds an
/// unread message, read as the drawer opens and cleared live.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final settings = AppSettings.instance;
  const secureStorage = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  const dot = ValueKey('drawer_chat_unread');

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (_) async => null);
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  void setChat({required bool enabled}) => settings.featureFlags.value = [
    FeatureFlag(
      key: FeatureFlag.chat,
      label: 'Chat',
      description: '',
      enabled: enabled,
    ),
  ];

  tearDown(() => settings.featureFlags.value = const []);

  Future<void> pumpDrawer(
    WidgetTester tester,
    Size size,
    ChatUnreadController unread,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
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

  for (final (label, size) in [
    ('narrow', const Size(360, 640)),
    ('wide', const Size(1280, 800)),
  ]) {
    testWidgets('dots the Chat row while a channel is unread, and clears '
        'it when another session reads it ($label)', (tester) async {
      setChat(enabled: true);
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
    setChat(enabled: true);
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

  testWidgets('asks for nothing while the chat beta is off', (tester) async {
    setChat(enabled: false);
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

    expect(lists, 0);
    expect(find.byKey(dot), findsNothing);
  });
}
