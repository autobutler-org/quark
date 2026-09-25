import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/settings/settings_profile_card.dart';

/// #2419: the Profile card on Settings → Account shows the user's picture or
/// initials, lets them choose a new one, and offers Remove only when there
/// is something to remove.
void main() {
  const narrowViewport = Size(360, 640);
  const wideViewport = Size(1280, 800);

  final pick = find.byKey(const ValueKey('settings_profile_pick'));
  final remove = find.byKey(const ValueKey('settings_profile_remove'));

  Future<List<String>> pumpCard(
    WidgetTester tester, {
    Size size = wideViewport,
    int? userId = 4,
    int? avatarVersion,
    bool isBusy = false,
    String? error,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final calls = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsProfileCard(
            userId: userId,
            username: 'ada lovelace',
            avatarVersion: avatarVersion,
            isBusy: isBusy,
            error: error,
            onPick: () => calls.add('pick'),
            onRemove: () => calls.add('remove'),
          ),
        ),
      ),
    );
    return calls;
  }

  for (final size in [narrowViewport, wideViewport]) {
    testWidgets('without a picture: initials, choose, no remove at $size', (
      tester,
    ) async {
      final calls = await pumpCard(tester, size: size);

      expect(find.byKey(const ValueKey('avatar_4')), findsOneWidget);
      expect(find.text('AL'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(remove, findsNothing);
      await tester.tap(pick);
      expect(calls, ['pick']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('with a picture: the versioned image and remove at $size', (
      tester,
    ) async {
      final calls = await pumpCard(
        tester,
        size: size,
        avatarVersion: 1790000000000,
      );

      final image = tester.widget<Image>(find.byType(Image));
      final url = Uri.parse((image.image as NetworkImage).url);
      expect(url.path, '/api/v0/users/4/avatar');
      expect(url.queryParameters['v'], '1790000000000');
      await tester.tap(remove);
      expect(calls, ['remove']);
    });
  }

  testWidgets('busy disables both buttons and shows the error', (tester) async {
    final calls = await pumpCard(
      tester,
      avatarVersion: 1,
      isBusy: true,
      error: 'That picture is larger than 10 MB. Pick a smaller one.',
    );

    await tester.tap(pick);
    await tester.tap(remove);
    expect(calls, isEmpty);
    expect(
      find.text('That picture is larger than 10 MB. Pick a smaller one.'),
      findsOneWidget,
    );
  });

  testWidgets('choosing waits for the Quark to name the account', (
    tester,
  ) async {
    final calls = await pumpCard(tester, userId: null);

    await tester.tap(pick);
    expect(calls, isEmpty);
  });
}
