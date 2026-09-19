import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/utils/file_browser_dialog_utils.dart';

/// Regression coverage for #1603: a name containing "/" used to be sent
/// straight through as the multipart filename while the router was pushed to
/// the same nested path. The upload endpoint drops the directory and writes at
/// the root, so the editor opened a path that did not exist and 404'd.
///
/// The invariant these tests pin: the dialog can only ever hand back a flat
/// name, which is exactly what the backend writes. See
/// internal/server/api/v0/files/upload_files_test.go for the other half.
void main() {
  /// Holds what the dialog handed back, so a test can read it after the
  /// dialog closes without awaiting inside the tester's pump loop.
  final outcome = _Outcome();

  Future<void> openPrompt(WidgetTester tester) async {
    outcome.reset();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              outcome.name = await promptForNewFileName(
                context,
                title: 'New Document',
                hintText: 'Document name',
              );
              outcome.completed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('New Document'), findsOneWidget);
  }

  testWidgets('a flat name is returned as typed', (tester) async {
    await openPrompt(tester);

    await tester.enterText(find.byType(TextField), '  meeting  ');
    await tester.pumpAndSettle();
    expect(find.textContaining('cannot contain'), findsNothing);

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(outcome.completed, isTrue);
    expect(outcome.name, 'meeting');
  });

  testWidgets('a name containing "/" is rejected, not flattened', (
    tester,
  ) async {
    await openPrompt(tester);

    await tester.enterText(find.byType(TextField), 'notes/meeting');
    await tester.pumpAndSettle();

    expect(find.text('The name cannot contain "/"'), findsOneWidget);

    // Create is disabled: tapping it must not close the dialog, and must not
    // hand back a nested name the backend would write somewhere else.
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.text('New Document'), findsOneWidget);
    expect(outcome.completed, isFalse);

    // Submitting from the keyboard is the same story.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('New Document'), findsOneWidget);
    expect(outcome.completed, isFalse);

    // Correcting the name clears the error and lets the dialog through.
    await tester.enterText(find.byType(TextField), 'meeting');
    await tester.pumpAndSettle();
    expect(find.textContaining('cannot contain'), findsNothing);

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(outcome.completed, isTrue);
    expect(outcome.name, 'meeting');
    expect(outcome.name, isNot(contains('/')));
  });

  testWidgets('cancelling returns null', (tester) async {
    await openPrompt(tester);

    await tester.enterText(find.byType(TextField), 'meeting');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(outcome.completed, isTrue);
    expect(outcome.name, isNull);
  });

  // #2012 / #2055: Docs and Sheets push the editor as soon as the file is
  // created, while the name dialog is still animating out. The dialog's
  // controller used to be disposed when its future completed, so the closing
  // TextField rebuilt against a disposed controller and the overlay failed a
  // `_dependents.isEmpty` assertion — a red screen instead of the editor.
  testWidgets('pushing a route while the dialog closes does not crash', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                final name = await promptForNewFileName(
                  context,
                  title: 'New Document',
                  hintText: 'Document name',
                );
                if (name == null || !context.mounted) return;
                // The upload the create flow awaits before it navigates.
                await Future<void>.delayed(const Duration(milliseconds: 10));
                if (!context.mounted) return;
                context.push('/editor');
              },
              child: const Text('open'),
            ),
          ),
        ),
        GoRoute(
          path: '/editor',
          builder: (context, state) =>
              const Scaffold(body: Text('editor', key: ValueKey('editor'))),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'meeting');
    await tester.tap(find.text('Create'));
    // Step through the exit transition frame by frame, the window the push
    // lands in.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 5));
    }
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('editor')), findsOneWidget);
  });

  testWidgets('an empty name keeps the dialog open', (tester) async {
    await openPrompt(tester);

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.text('New Document'), findsOneWidget);
    expect(outcome.completed, isFalse);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(outcome.name, isNull);
  });
}

class _Outcome {
  String? name;
  bool completed = false;

  void reset() {
    name = null;
    completed = false;
  }
}
