import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/slides/properties/slide_commit_field.dart';

/// The state the slide editor's fields share: one commit per edit, the
/// refused text put back, and the shown text following [text] when the
/// field is not being typed in.
void main() {
  Widget host(String text, List<String> commits, {String? Function()? reply}) =>
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SlideCommitField(
                text: text,
                onCommit: (typed) {
                  commits.add(typed);
                  return reply?.call();
                },
                builder: (context, controller, focusNode, commit) => TextField(
                  key: const ValueKey('field'),
                  controller: controller,
                  focusNode: focusNode,
                  onSubmitted: (_) => commit(),
                ),
              ),
              const TextField(key: ValueKey('other')),
            ],
          ),
        ),
      );

  testWidgets('Enter and the focus loss after it commit once', (tester) async {
    final commits = <String>[];
    await tester.pumpWidget(host('a', commits));
    await tester.enterText(find.byKey(const ValueKey('field')), 'b');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.tap(find.byKey(const ValueKey('other')));
    await tester.pump();
    expect(commits, ['b']);
  });

  testWidgets('the text onCommit returns replaces what was typed', (
    tester,
  ) async {
    await tester.pumpWidget(host('5', [], reply: () => '5'));
    await tester.enterText(find.byKey(const ValueKey('field')), 'x');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('a new text shows while the field is not focused', (
    tester,
  ) async {
    await tester.pumpWidget(host('a', []));
    await tester.pumpWidget(host('c', []));
    expect(find.text('c'), findsOneWidget);
  });
}
