import 'package:flutter/widgets.dart';

/// Whether the document editor should take focus back now that the app has
/// come back to the foreground (#1856).
///
/// On web, switching to another browser tab and back leaves the editor
/// silently unfocused: Flutter's text-input shim does not re-attach its hidden
/// DOM input after the browser's visibility-change cycle, so the caret is gone
/// and the next keystroke goes nowhere until you click into the document
/// again. Nothing in the app drops that focus — this is upstream — so the page
/// watches the lifecycle and asks for focus back.
///
/// [previous] and [current] are consecutive [AppLifecycleState]s: a tab
/// switch runs resumed → inactive/hidden and back, so a resume that follows
/// anything other than resumed is the app returning.
///
/// The conditions, and why each one is there:
///
/// - [isWeb], because only web has a tab to switch away from. Refocusing on
///   mobile would pop the soft keyboard every time the user came back from
///   another app, which is worse than the bug.
/// - [isEditing], because a read-only document has nothing to type into and
///   the editor draws no caret there anyway (#1853).
/// - not [findBarOpen], because the find field is the one other thing on the
///   page a writer can be typing in, and taking focus off it on resume would
///   be the same bug pointed the other way.
///
/// Deliberately not checking whether the editor still reports focus: after a
/// tab switch Flutter can believe the node is focused while the browser
/// disagrees, which is the state this is here to repair.
bool shouldRefocusEditorOnResume({
  required AppLifecycleState previous,
  required AppLifecycleState current,
  required bool isWeb,
  required bool isEditing,
  required bool findBarOpen,
}) =>
    isWeb &&
    isEditing &&
    !findBarOpen &&
    current == AppLifecycleState.resumed &&
    previous != AppLifecycleState.resumed;
