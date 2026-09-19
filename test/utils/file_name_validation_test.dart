import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/models/move_rename_result.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_browser_dialog_utils.dart';

/// #2076 and #2074: a blank or overlong name closed the rename and new
/// folder dialogs and did nothing, with no word about why. The dialogs now
/// keep the name, say what is wrong with it, and only offer the button for a
/// name the Quark can write.
void main() {
  final tooLong = 'a' * (maxFileNameBytes + 1);

  group('fileNameProblem', () {
    test('accepts an ordinary name', () {
      expect(fileNameProblem('report.pdf'), isNull);
    });

    test('calls an empty or all-space name blank', () {
      expect(fileNameProblem(''), Errors.nameBlank);
      expect(fileNameProblem('   '), Errors.nameBlank);
    });

    test('allows exactly the filesystem limit and no more', () {
      expect(fileNameProblem('a' * maxFileNameBytes), isNull);
      expect(fileNameProblem(tooLong), Errors.nameTooLong);
    });

    test('counts bytes, not characters', () {
      // "é" is two bytes in UTF-8: 128 of them is 256 bytes.
      expect(fileNameProblem('é' * 128), Errors.nameTooLong);
      expect(fileNameProblem('é' * 127), isNull);
    });
  });

  group('new folder', () {
    late _Outcome<String> outcome;

    Future<void> open(WidgetTester tester) async {
      outcome = _Outcome();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                outcome.value = await promptForFolderName(context);
                outcome.completed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('a blank name keeps the dialog open', (tester) async {
      await open(tester);
      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();

      await tester.tap(find.text('Create'));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('New Folder'), findsOneWidget);
      expect(outcome.completed, isFalse);
    });

    testWidgets('an overlong name says so and keeps the dialog open', (
      tester,
    ) async {
      await open(tester);
      await tester.enterText(find.byType(TextField), tooLong);
      await tester.pump();

      expect(find.text(Errors.nameTooLong), findsOneWidget);
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(outcome.completed, isFalse);

      await tester.enterText(find.byType(TextField), 'Photos');
      await tester.pump();
      expect(find.text(Errors.nameTooLong), findsNothing);
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(outcome.value, 'Photos');
    });
  });

  group('move / rename', () {
    late _Outcome<MoveRenameResult> outcome;

    setUp(() {
      // The destination picker lists folders; an empty listing is enough.
      sharedHttpClientFactory = () =>
          MockClient((_) async => http.Response('[]', 200));
    });

    tearDown(() {
      resetSharedHttpClient();
      sharedHttpClientFactory = buildLocalTrustHttpClient;
    });

    Future<void> open(WidgetTester tester) async {
      outcome = _Outcome();
      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                outcome.value = await promptForMoveRenamePath(
                  context,
                  initialName: 'notes.txt',
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
      expect(find.text('Move / Rename'), findsOneWidget);
    }

    Finder nameField() => find.byType(TextField).last;

    testWidgets('a blank name says so and cannot be saved', (tester) async {
      await open(tester);
      await tester.enterText(nameField(), '   ');
      await tester.pump();

      expect(find.text(Errors.nameBlank), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Move / Rename'), findsOneWidget);
      expect(outcome.completed, isFalse);
    });

    testWidgets('an overlong name says so and cannot be saved', (tester) async {
      await open(tester);
      await tester.enterText(nameField(), tooLong);
      await tester.pump();

      expect(find.text(Errors.nameTooLong), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(outcome.completed, isFalse);
    });

    testWidgets('a good name is saved', (tester) async {
      await open(tester);
      await tester.enterText(nameField(), 'todo.txt');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(outcome.value?.targetInput, 'todo.txt');
    });
  });
}

class _Outcome<T> {
  T? value;
  bool completed = false;
}
