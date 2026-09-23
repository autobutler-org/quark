---
name: quark-widgets-widget-tests
description: Write or extend a widget test for a quark_widgets widget, or for any data-in, callbacks-out Flutter widget. Use when adding a widget, changing a widget's inputs or callbacks, filling gaps in an existing widget test, or reproducing a layout defect that only appears on a narrow viewport.
---

# Testing a data-in, callbacks-out widget

These widgets take immutable values and handlers. They never fetch, never
navigate, and never read global state, so a test is just: build it with data,
look at what it drew, tap it, and check what came out. No mocks, no service
fakes, no `WidgetsFlutterBinding` dance. A file should run in well under a
second.

The whole job is coverage of the widget's own surface. Work the checklist
below top to bottom, and skip a line only when the widget genuinely has no
such thing (no callbacks, no per-item keys). Everything else is a gap.

## The pump helper

Every case pumps through one helper, so a layout that only works on one
viewport fails the same way in every file. Put it at `test/support/pump.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The narrow viewport every widget has to survive: a small phone in portrait.
const Size narrowViewport = Size(360, 640);

/// The wide viewport: a desktop window.
const Size wideViewport = Size(1280, 800);

/// Pumps [child] inside Quark's theme at [size].
Future<void> pumpAt(
  WidgetTester tester,
  Widget child, {
  Size size = wideViewport,
  Brightness brightness = Brightness.dark,
  bool scaffold = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: QuarkTheme.from(
        brightness == Brightness.dark ? QuarkTokens.dark : QuarkTokens.light,
        brightness,
      ),
      home: scaffold ? Scaffold(body: child) : child,
    ),
  );
  await tester.pump();
}

/// Runs [body] against both [narrowViewport] and [wideViewport].
void testBothViewports(
  String description,
  Future<void> Function(WidgetTester tester, Size size) body,
) {
  for (final size in [narrowViewport, wideViewport]) {
    final label = size == narrowViewport ? 'narrow' : 'wide';
    testWidgets('$description ($label)', (tester) => body(tester, size));
  }
}
```

It lives under `test/`, not under `lib/`, on purpose. It imports
`package:flutter_test/flutter_test.dart`, and a library under `lib/` that does
that forces `flutter_test` into the package's real `dependencies`, where it
lands in every consuming app's dependency graph. Copy the helper into your own
package's `test/support/` instead of importing it from here.

## The checklist

Each item is one or more cases in the test file. The assertion patterns are
exact; substitute your widget and its keys.

### 1. Every declared state renders

A widget that lists things declares `isLoading`, `error`, an empty list, a
populated list, and a selection. Each is a case, and each asserts what the
*other* states must not show, so a state rendering on top of another one
fails.

```dart
testBothViewports('shows a spinner while loading', (tester, size) async {
  await pumpAt(tester, const ThingList(items: [], isLoading: true), size: size);
  expect(find.byType(QuarkLoader), findsOneWidget);
  expect(find.text('Nothing here yet'), findsNothing);
});

testBothViewports('shows the empty copy when there is nothing', (tester, size) async {
  await pumpAt(tester, const ThingList(items: []), size: size);
  expect(find.text('Nothing here yet'), findsOneWidget);
  expect(find.byType(QuarkLoader), findsNothing);
});

testBothViewports('renders the error the caller handed it', (tester, size) async {
  await pumpAt(tester, const ThingList(items: [], error: 'Host unreachable'), size: size);
  // The package never composes error copy. It renders the caller's string.
  expect(find.text('Host unreachable'), findsOneWidget);
});

testBothViewports('renders one row per item', (tester, size) async {
  await pumpAt(tester, ThingList(items: threeThings), size: size);
  expect(find.byKey(const ValueKey('thing_row_a')), findsOneWidget);
  expect(find.text('Beta'), findsOneWidget);
});

testBothViewports('marks the selected item', (tester, size) async {
  await pumpAt(tester, ThingList(items: threeThings, selectedIds: const {'b'}), size: size);
  expect(find.byIcon(Icons.check), findsOneWidget);
});
```

### 2. Both viewports lay out cleanly

`tester.takeException()` returns the overflow error a `RenderFlex` throws, so
this one line is the whole narrow-viewport regression test.

```dart
testBothViewports('lays out without an exception', (tester, size) async {
  await pumpAt(tester, ThingList(items: threeThings), size: size);
  expect(tester.takeException(), isNull);
});
```

### 3. Every callback fires exactly once, with the right value

Collect into a list, never a bool. A list catches a second fire; a bool hides
it. Tap the keyed element, not the label, so a failure names the part that was
hit.

```dart
testBothViewports('reports the item that was tapped', (tester, size) async {
  final selected = <String>[];
  await pumpAt(
    tester,
    ThingList(items: threeThings, onSelect: selected.add),
    size: size,
  );

  await tester.tap(find.byKey(const ValueKey('thing_row_b')));
  await tester.pump();

  expect(selected, ['b']);
});
```

For a widget with several actions, drive them all in one case and assert the
whole sequence, which pins the order too:

```dart
expect(events, ['selectAll', 'delete', 'cancel']);
```

A callback the caller did not supply must disable its control rather than
throw:

```dart
testWidgets('dims the delete button when deleting is not offered', (tester) async {
  await pumpAt(tester, ThingList(items: threeThings));
  final button = tester.widget<IconButton>(
    find.byKey(const ValueKey('thing_delete_b')),
  );
  expect(button.onPressed, isNull);
});
```

### 4. Every documented key prefix is present, per item

The class doc lists the prefixes so an end-to-end script can write
`tap #thing_row_b`. Loop the items, so adding a fourth cannot silently lose a
key.

```dart
testWidgets('emits every documented key for every item', (tester) async {
  await pumpAt(tester, ThingList(items: threeThings));
  for (final thing in threeThings) {
    expect(find.byKey(ValueKey('thing_row_${thing.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('thing_delete_${thing.id}')), findsOneWidget);
  }
});
```

### 5. Both token sets render

A hardcoded color survives dark and breaks light. Read the color back and
compare it to the token, so the case fails when someone types a literal.

```dart
for (final (label, brightness, tokens) in [
  ('dark', Brightness.dark, QuarkTokens.dark),
  ('light', Brightness.light, QuarkTokens.light),
]) {
  testWidgets('$label: colors come from the tokens', (tester) async {
    await pumpAt(tester, ThingList(items: threeThings), brightness: brightness);

    expect(tester.takeException(), isNull);
    final box = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('thing_row_a')),
    );
    expect((box.decoration as BoxDecoration).color, tokens.card);
  });
}
```

### 6. Icon-only buttons name themselves

Sweep the tree rather than listing tooltips, so a button added later is
covered without anyone editing the test.

```dart
testWidgets('every icon-only button carries a tooltip', (tester) async {
  await pumpAt(tester, ThingList(items: threeThings));
  for (final button in tester.widgetList<IconButton>(find.byType(IconButton))) {
    expect(button.tooltip, isNotNull, reason: 'an icon alone says nothing');
  }
});
```

If the control is not an `IconButton`, wrap it in `Semantics(label: ...)` and
assert `find.bySemanticsLabel('Delete selected')` instead.

### 7. Long text and many items do not overflow

The narrow viewport plus a long name is where `Row` children that were never
given `Expanded` or `TextOverflow.ellipsis` fall over.

```dart
testBothViewports('survives a long name and a long list', (tester, size) async {
  await pumpAt(
    tester,
    ThingList(
      items: [
        for (var i = 0; i < 200; i++) Thing(id: '$i', name: 'Vacation ' * 30),
      ],
    ),
    size: size,
  );
  expect(tester.takeException(), isNull);
});
```

## Where the file goes

One test file per widget file, mirroring the source tree:

| Source | Test |
| --- | --- |
| `lib/src/<group>/<name>.dart` | `test/<group>/<name>_test.dart` |
| `lib/src/models/<name>.dart` | `test/models/<name>_test.dart` |

Shared helpers go under `test/support/` and are imported relatively
(`import '../support/pump.dart';`). Open the file with a `///` comment saying
what the widget is for and which defect the file guards against, if any. Name
a case as a sentence about behavior ("reports the album that was tapped, at
any depth"), not about mechanics ("test onTap").

## Running them

```sh
cd packages/quark_widgets
flutter test                                  # the whole package
flutter test test/core/thing_list_test.dart   # one file
flutter test --plain-name 'reports the item'  # one case
```

From the repo root, `make -C packages/quark_widgets test/unit` does the same,
and `make -C packages/quark_widgets check` runs
`dart format --set-exit-if-changed` and `flutter analyze` over the package.

## References

- [`references/test_template.dart`](references/test_template.dart): a complete
  test file walking the whole checklist. Copy it and rename.
- [`references/examples.md`](references/examples.md): three real test files in
  this package, and what each is worth reading for.
