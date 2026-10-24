import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/file_browser_dialog_utils.dart';

void main() {
  testWidgets('a second message queues behind the first', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    showMessage(context, 'first');
    showMessage(context, 'second');
    await tester.pumpAndSettle();
    expect(find.text('first'), findsOneWidget);
    expect(find.text('second'), findsNothing);

    // Flutter's default four seconds, then the queued one.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('first'), findsNothing);
    expect(find.text('second'), findsOneWidget);
  });

  testWidgets('an action rides on the bar', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    showMessage(
      context,
      'Deleted',
      action: SnackBarAction(label: 'Undo', onPressed: () {}),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(SnackBarAction, 'Undo'), findsOneWidget);
  });
}
