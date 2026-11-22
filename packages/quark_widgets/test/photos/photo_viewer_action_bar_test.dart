import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  const keys = [
    'photo_viewer_action_share',
    'photo_viewer_action_favorite',
    'photo_viewer_action_info',
    'photo_viewer_action_delete',
  ];

  testWidgets('runs each action', (tester) async {
    final events = <String>[];
    await pumpAt(
      tester,
      PhotoViewerActionBar(
        onShare: () => events.add('share'),
        onFavorite: () => events.add('favorite'),
        onInfo: () => events.add('info'),
        onDelete: () => events.add('delete'),
      ),
      size: narrowViewport,
    );

    for (final key in keys) {
      await tester.tap(find.byKey(ValueKey(key)));
    }

    expect(events, ['share', 'favorite', 'info', 'delete']);
  });

  testBothViewports('labels every action and keeps 44 px targets', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      PhotoViewerActionBar(
        onShare: () {},
        onFavorite: () {},
        onInfo: () {},
        onDelete: () {},
      ),
      size: size,
    );

    for (final label in ['Share', 'Favorite', 'Info', 'Delete']) {
      expect(find.text(label), findsOneWidget);
    }
    for (final key in keys) {
      final rect = tester.getRect(find.byKey(ValueKey(key)));
      expect(rect.width, greaterThanOrEqualTo(44));
      expect(rect.height, greaterThanOrEqualTo(44));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaves out an action without a callback', (tester) async {
    await pumpAt(tester, PhotoViewerActionBar(onInfo: () {}));

    expect(find.byKey(const ValueKey('photo_viewer_action_info')), findsOne);
    expect(
      find.byKey(const ValueKey('photo_viewer_action_share')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('photo_viewer_action_delete')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('photo_viewer_action_favorite')),
      findsNothing,
    );
  });

  testWidgets('reads Unfavorite and selects Info when they are on', (
    tester,
  ) async {
    await pumpAt(
      tester,
      PhotoViewerActionBar(
        isFavorite: true,
        infoOpen: true,
        onFavorite: () {},
        onInfo: () {},
      ),
    );

    expect(find.text('Unfavorite'), findsOneWidget);
    expect(find.byIcon(QuarkIcons.star), findsOneWidget);
    expect(find.byIcon(QuarkIcons.info), findsOneWidget);
  });
}
