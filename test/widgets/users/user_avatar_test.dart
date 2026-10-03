import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/users/user_avatar.dart';

/// #2603: an avatar always sits beside the account's name, so its picture is
/// decoration a screen reader skips rather than an unlabeled image.
void main() {
  testWidgets('the profile picture is left out of semantics', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: UserAvatar(userId: 1, name: 'Ada', version: 7)),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.excludeFromSemantics, isTrue);
  });
}
