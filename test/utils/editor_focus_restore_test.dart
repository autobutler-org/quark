import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/editor_focus_restore.dart';

// Switching browser tabs away and back left the docs editor unfocused, so the
// caret was gone and typing went nowhere until you clicked back into the
// document (#1856). These pin down when the page asks for focus back — and,
// as much, when it must not.
void main() {
  bool decide({
    AppLifecycleState previous = AppLifecycleState.hidden,
    AppLifecycleState current = AppLifecycleState.resumed,
    bool isWeb = true,
    bool isEditing = true,
    bool findBarOpen = false,
  }) => shouldRefocusEditorOnResume(
    previous: previous,
    current: current,
    isWeb: isWeb,
    isEditing: isEditing,
    findBarOpen: findBarOpen,
  );

  test('refocuses when the tab comes back to an editable document', () {
    expect(decide(), isTrue);
  });

  test('refocuses however the browser reported the tab going away', () {
    for (final away in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.paused,
    ]) {
      expect(decide(previous: away), isTrue, reason: away.name);
    }
  });

  test('does nothing while the app is still going away', () {
    for (final away in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
    ]) {
      expect(decide(current: away), isFalse, reason: away.name);
    }
  });

  test('does nothing on a resume that follows a resume', () {
    expect(decide(previous: AppLifecycleState.resumed), isFalse);
  });

  test('leaves a read-only document alone', () {
    expect(decide(isEditing: false), isFalse);
  });

  test('leaves focus with the find bar when it is open', () {
    expect(decide(findBarOpen: true), isFalse);
  });

  test('does not steal focus on mobile, where the keyboard would follow', () {
    expect(decide(isWeb: false), isFalse);
  });
}
