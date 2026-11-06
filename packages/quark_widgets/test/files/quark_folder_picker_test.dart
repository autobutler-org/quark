/// [QuarkFolderPicker] renders loading, empty, error, and a folder list, and
/// reports opens, up, and "Save here" without overflowing a phone.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

const _documents = QuarkFolderEntry(path: '/Documents', name: 'Documents');
const _photos = QuarkFolderEntry(path: '/Photos/2024', name: '2024');
const _folders = [_documents, _photos];

void _noop() {}

QuarkFolderPicker _picker({
  List<QuarkFolderEntry> folders = _folders,
  String currentPath = '/',
  String currentName = 'My files',
  bool canGoUp = true,
  bool isLoading = false,
  String? error,
  ValueChanged<QuarkFolderEntry>? onOpen,
  VoidCallback? onUp = _noop,
  VoidCallback? onSelect,
}) {
  return QuarkFolderPicker(
    folders: folders,
    currentPath: currentPath,
    currentName: currentName,
    canGoUp: canGoUp,
    isLoading: isLoading,
    error: error,
    onOpen: onOpen ?? (_) {},
    onUp: onUp,
    onSelect: onSelect ?? _noop,
  );
}

void main() {
  testBothViewports('lists the folders in the current directory', (
    tester,
    size,
  ) async {
    await pumpAt(tester, _picker(), size: size);

    expect(tester.takeException(), isNull);
    expect(find.text('My files'), findsOneWidget);
    expect(find.text('/'), findsOneWidget);
    expect(find.text('Documents'), findsOneWidget);
    expect(find.text('2024'), findsOneWidget);
    expect(find.text('Save here'), findsOneWidget);
    expect(find.text('This folder is empty'), findsNothing);
    expect(find.byType(QuarkLoader), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(QuarkIcons.folder_outlined), findsNWidgets(2));
    expect(find.byTooltip('Up one level'), findsOneWidget);
    for (final folder in _folders) {
      expect(
        find.byKey(
          ValueKey('folder_picker_row_${folder.path.replaceAll('/', '_')}'),
        ),
        findsOneWidget,
      );
    }
    expect(
      find.byKey(const ValueKey('folder_picker_row__Photos_2024')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('folder_picker_up')), findsOneWidget);
    expect(find.byKey(const ValueKey('folder_picker_select')), findsOneWidget);
  });

  testBothViewports('says the folder is empty and still offers save', (
    tester,
    size,
  ) async {
    await pumpAt(tester, _picker(folders: const []), size: size);

    expect(tester.takeException(), isNull);
    expect(find.text('This folder is empty'), findsOneWidget);
    expect(find.text('Save here'), findsOneWidget);
    expect(find.text('Documents'), findsNothing);
    expect(find.byType(QuarkLoader), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    final save = tester.widget<FilledButton>(
      find.byKey(const ValueKey('folder_picker_select')),
    );
    expect(save.onPressed, isNotNull);
  });

  testBothViewports('shows a loader and no empty copy while loading', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      _picker(folders: const [], isLoading: true),
      size: size,
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(QuarkLoader), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('This folder is empty'), findsNothing);
    expect(find.text('Documents'), findsNothing);
    expect(find.text('Save here'), findsOneWidget);
  });

  testBothViewports('shows the error string and no spinner', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      _picker(isLoading: true, error: 'Host unreachable'),
      size: size,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Host unreachable'), findsOneWidget);
    expect(find.byType(QuarkLoader), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('This folder is empty'), findsNothing);
    expect(find.text('Documents'), findsNothing);
    expect(find.text('2024'), findsNothing);
    expect(find.text('Save here'), findsOneWidget);
  });

  testBothViewports('scrolls a long list and a long name', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      _picker(
        currentName: 'Vacation photos ' * 12,
        currentPath: '/${'nested/' * 30}end',
        folders: [
          for (var i = 0; i < 40; i++)
            QuarkFolderEntry(
              path: '/folder/$i',
              name: i == 0 ? 'Vacation ' * 30 : 'Folder $i',
            ),
        ],
      ),
      size: size,
    );

    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('Folder 39'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Folder 39'), findsOneWidget);
  });

  testBothViewports('lays out inside a scrolling parent', (tester, size) async {
    await pumpAt(
      tester,
      SingleChildScrollView(
        child: _picker(currentName: 'Vacation photos ' * 12),
      ),
      size: size,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Documents'), findsOneWidget);
    expect(find.text('Save here'), findsOneWidget);
  });

  testWidgets('reports the folder whose row was tapped', (tester) async {
    final opened = <QuarkFolderEntry>[];
    await pumpAt(tester, _picker(onOpen: opened.add));

    await tester.tap(
      find.byKey(const ValueKey('folder_picker_row__Photos_2024')),
    );
    await tester.pump();

    expect(opened, hasLength(1));
    expect(opened.single.path, '/Photos/2024');
    expect(opened.single.name, '2024');
  });

  testWidgets('reports the up control', (tester) async {
    final events = <String>[];
    await pumpAt(tester, _picker(onUp: () => events.add('up')));

    await tester.tap(find.byKey(const ValueKey('folder_picker_up')));
    await tester.pump();

    expect(events, ['up']);
  });

  testWidgets('reports save here for the folder on screen', (tester) async {
    final events = <String>[];
    await pumpAt(
      tester,
      _picker(folders: const [], onSelect: () => events.add('select')),
    );

    await tester.tap(find.byKey(const ValueKey('folder_picker_select')));
    await tester.pump();

    expect(events, ['select']);
    expect(find.text('This folder is empty'), findsOneWidget);
  });

  testWidgets('hides the up control when the caller cannot go up', (
    tester,
  ) async {
    await pumpAt(tester, _picker(canGoUp: false, onUp: _noop));

    expect(find.byKey(const ValueKey('folder_picker_up')), findsNothing);
    expect(find.byTooltip('Up one level'), findsNothing);
  });

  testWidgets('disables the up control when going up is not offered', (
    tester,
  ) async {
    await pumpAt(tester, _picker(onUp: null));

    final button = tester.widget<TextButton>(
      find.byKey(const ValueKey('folder_picker_up')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('keeps listed folders on screen through a refresh', (
    tester,
  ) async {
    await pumpAt(tester, _picker(isLoading: true));

    expect(find.text('Documents'), findsOneWidget);
    expect(find.byType(QuarkLoader), findsNothing);
    expect(find.text('This folder is empty'), findsNothing);
  });

  testWidgets('every icon-only button carries a tooltip', (tester) async {
    await pumpAt(tester, _picker());

    expect(find.byType(IconButton), findsNothing);
  });

  for (final (label, brightness, tokens) in [
    ('dark', Brightness.dark, QuarkTokens.dark),
    ('light', Brightness.light, QuarkTokens.light),
  ]) {
    testWidgets('$label: colors come from the tokens', (tester) async {
      await pumpAt(tester, _picker(), brightness: brightness);

      expect(tester.takeException(), isNull);
      final icon = tester.widget<Icon>(
        find.byIcon(QuarkIcons.folder_outlined).first,
      );
      expect(icon.color, tokens.secondaryForeground);
      final title = tester.widget<Text>(find.text('My files'));
      expect(title.style?.color, tokens.foreground);
      final path = tester.widget<Text>(find.text('/'));
      expect(path.style?.color, tokens.mutedForeground);

      await pumpAt(
        tester,
        _picker(folders: const [], error: 'Host unreachable'),
        brightness: brightness,
      );
      final message = tester.widget<Text>(find.text('Host unreachable'));
      expect(message.style?.color, tokens.error);
    });
  }
}
