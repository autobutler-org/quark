import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/overlay_history.dart';

// flutter test runs the non-web stub, a plain navigator push. Browser history
// cannot be driven from here; the web path pushes an entry at the current URL.
void main() {
  testWidgets('returns the route result and shows the page underneath again', (
    tester,
  ) async {
    Future<bool?>? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Column(
                children: [
                  const Text('home'),
                  TextButton(
                    onPressed: () {
                      result = pushWithBrowserBack<bool>(
                        context,
                        MaterialPageRoute<bool>(
                          builder: (context) => Scaffold(
                            body: TextButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              child: const Text('close'),
                            ),
                          ),
                        ),
                      );
                    },
                    child: const Text('open'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    expect(find.text('home'), findsOneWidget);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('close'), findsOneWidget);

    await tester.tap(find.text('close'));
    await tester.pumpAndSettle();

    expect(await result, isTrue);
    expect(find.text('home'), findsOneWidget);
    expect(find.text('close'), findsNothing);
  });
}
