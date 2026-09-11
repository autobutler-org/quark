import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
// QuillNativeProvider, the seam for replacing the plugin under test.
// ignore: experimental_member_use
import 'package:flutter_quill/internal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/pages/document_editor_page.dart';
import 'package:quark/utils/document_paste.dart';

/// Ctrl/Cmd+V has to reach the page when flutter_quill would paste nothing and
/// say nothing about it — a read-only document, or a browser that will not
/// share the clipboard — and has to stay out of the way otherwise (#1857).
void main() {
  // flutter_quill reads modifiers from the host OS (dart:io), and key
  // simulation needs the matching platform to set the flags — so pin both to
  // this machine, the way the find-shortcut test does.
  final hostPlatform = Platform.isMacOS
      ? TargetPlatform.macOS
      : TargetPlatform.linux;
  final hostModifier = Platform.isMacOS
      ? LogicalKeyboardKey.meta
      : LogicalKeyboardKey.control;

  // A paste that is *not* intercepted runs flutter_quill's own, which reaches
  // for the quill_native_bridge plugin — unregistered under `flutter test`,
  // where it throws "isSupported() has not been implemented". The package's
  // own stub answers "nothing supported" instead, which is what a browser
  // without the Clipboard API answers too.
  setUp(() => QuillNativeProvider.instance = _NoNativeBridge());
  tearDown(() => QuillNativeProvider.instance = null);

  Future<void> pressPaste(WidgetTester tester) async {
    await tester.sendKeyDownEvent(hostModifier);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(hostModifier);
    await tester.pumpAndSettle();
  }

  Future<List<DocumentPasteAction>> pumpAndPaste(
    WidgetTester tester,
    DocumentPasteAction action,
  ) async {
    final intercepted = <DocumentPasteAction>[];
    final controller = QuillController.basic();
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates:
            FlutterQuillLocalizations.localizationsDelegates,
        home: Scaffold(
          body: QuillEditor.basic(
            controller: controller,
            focusNode: focus,
            config: QuillEditorConfig(
              // ignore: experimental_member_use
              onKeyPressed: (event, node) =>
                  quillPasteKeyInterceptor(event, action, intercepted.add),
            ),
          ),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    await pressPaste(tester);
    return intercepted;
  }

  testWidgets('an unreachable clipboard is reported once', (tester) async {
    debugDefaultTargetPlatformOverride = hostPlatform;

    final intercepted = await pumpAndPaste(
      tester,
      DocumentPasteAction.unavailable,
    );

    expect(intercepted, [
      DocumentPasteAction.unavailable,
    ], reason: 'key-up must not report a second time');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a read-only document asks to start editing', (tester) async {
    debugDefaultTargetPlatformOverride = hostPlatform;

    final intercepted = await pumpAndPaste(
      tester,
      DocumentPasteAction.editThenPaste,
    );

    expect(intercepted, [DocumentPasteAction.editThenPaste]);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('an ordinary paste is never intercepted', (tester) async {
    debugDefaultTargetPlatformOverride = hostPlatform;

    final intercepted = await pumpAndPaste(
      tester,
      DocumentPasteAction.passThrough,
    );

    expect(intercepted, isEmpty);
    debugDefaultTargetPlatformOverride = null;
  });

  test('plain V is left to the editor', () {
    final intercepted = <DocumentPasteAction>[];

    final result = quillPasteKeyInterceptor(
      const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyV,
        logicalKey: LogicalKeyboardKey.keyV,
        timeStamp: Duration.zero,
      ),
      DocumentPasteAction.unavailable,
      intercepted.add,
    );

    expect(result, isNull);
    expect(intercepted, isEmpty);
  });
}

/// Answers "nothing supported", the way a browser without the Clipboard API
/// does. The real bridge is a plugin, unregistered under `flutter test`.
class _NoNativeBridge extends QuillNativeBridge {
  @override
  Future<bool> isSupported(QuillNativeBridgeFeature feature) async => false;
}
