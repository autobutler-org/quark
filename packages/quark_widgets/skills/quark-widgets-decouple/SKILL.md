---
name: quark-widgets-decouple
description: Migrate a StatefulWidget or page that fetches data or holds domain state into stateless widgets plus a ChangeNotifier controller. Use when a screen calls a service from its State, when setState and business logic are tangled together, when a page has grown private _build methods, or when a widget cannot be tested because it pulls in routing, auth, or HTTP.
---

# Decoupling a page from its state

The target shape is three layers with one direction of dependency:

```
page (StatefulWidget)  ->  controller (ChangeNotifier)  ->  service functions
   |
   +-> widgets (StatelessWidget, data in, callbacks out)
```

The controller holds domain state and makes every service call. The widgets
render values and emit callbacks and know nothing else. The page owns the
controller, rebuilds through `ListenableBuilder`, and keeps navigation,
dialogs, snack bars, and error copy.

What this buys: the controller is testable with plain functions and no mocking
library, the widgets are testable in milliseconds with no HTTP or router, and
a layout defect reproduces in a headless widget test instead of on a device.

Work the steps in order. Do not skip step 1; the inventory is what stops you
lifting the wrong state.

## 1. Inventory before you move anything

List, from the current file:

- every field in the `State`, with its name and line
- every service call, with the service, method, and line
- every widget built inline (a `_build*` method, a local `Widget` function, a
  private `_Foo extends StatelessWidget`), with what data it needs and what it
  does when tapped

**Why:** the split falls out of this list mechanically. Written down, a field
that turns out to be derived (`_filtered`, recomputed from `_items` and
`_query`) is visible as something to delete rather than lift, and an inline
widget used twice is visible as one widget rather than two.

## 2. Classify each piece of state

Two buckets:

| Domain, lift to the controller | Flutter-forced, stays local |
| --- | --- |
| the fetched list, the selected ids, the expanded ids | `AnimationController` |
| the chosen album, sort order, filter, query | `FocusNode` |
| `isLoading`, `error`, `hasMore`, the page cursor | `TextEditingController` |
| favorites, dirty flags, edit-in-progress values | `ScrollController` |
| anything a test would want to set up directly | hover and pressed visuals |

**Why:** Flutter-forced state has a lifecycle Flutter owns (create in
`initState`, dispose in `dispose`) and no meaning outside the widget tree.
Lifting it buys nothing and costs you a controller that cannot be tested
without a `WidgetTester`. Everything else has meaning without a tree, so it
belongs where a test can set it in one line.

Even for the local bucket, expose the outcome if a caller could care: keep the
`TextEditingController` in the widget, send the submitted text out through
`onSubmitted`.

## 3. Write the controller

A `ChangeNotifier` with fields for state, methods for actions, and its service
calls arriving as function parameters that default to the real
implementations.

```dart
class ThingsController extends ChangeNotifier {
  ThingsController({
    Future<List<Thing>> Function() fetchThings = ThingsService.list,
    Future<void> Function(String id) deleteThing = ThingsService.delete,
  }) : _fetchThings = fetchThings,
       _deleteThing = deleteThing;

  final Future<List<Thing>> Function() _fetchThings;
  final Future<void> Function(String id) _deleteThing;
  // ...
}
```

**Why the injectable functions:** a test constructs
`ThingsController(fetchThings: () async => [aThing])` and covers the load, the
action, and the error path with no mocking library and no HTTP. Defaults
pointing at the real static methods mean the page still writes
`ThingsController()`.

Rules for the body:

- Expose state through getters over private fields, so only the controller
  writes them.
- Every method that changes state ends in `notifyListeners()`, once, after the
  last write. **Why:** two notifications is two rebuilds.
- Catch at the boundary: set `error` and clear `isLoading` in a `finally`, so
  a thrown service call cannot leave a spinner up forever.
- Guard against a stale response overwriting a newer one when the user can
  start a second load. **Why:** a slow first request landing after a fast
  second one shows the wrong list, and it only reproduces under load.
- Never touch `BuildContext`, `Navigator`, `ScaffoldMessenger`, or a
  `SnackBar`. **Why:** the moment it does, testing it needs a widget tree.

See [`references/controller_template.dart`](references/controller_template.dart)
for the full skeleton with load, action, and error paths.

## 4. Define value types for what the widgets render

Small immutable classes: `final` fields, a `const` constructor, `==` and
`hashCode` if anything compares them.

```dart
class ThingItem {
  const ThingItem({required this.id, required this.name, required this.isFavorite});
  final String id;
  final String name;
  final bool isFavorite;
}
```

**Why:** the widget package must not import your app models, or it inherits
their JSON parsing, their service imports, and their churn. The controller
maps app model to value type in one place, which is also the one place a
rename lands.

## 5. Split the tree into data-in, callbacks-out widgets

Each `_build*` method and inline widget from step 1 becomes a
`StatelessWidget` taking values and handlers.

- One widget class per file, public, named after the class. No private
  `_Part` classes inside another file and no `_build*` methods; a part of one
  parent lives in a subdirectory named after the parent. Small files show
  what can be reused.
- Constructor takes `super.key`, `final` fields, `const` where possible.
- Loading, empty, and error are explicit inputs (`isLoading`, `error`), and
  the widget renders each case. It never decides when to load.
- Anything that needs the network is a builder parameter
  (`thumbnailBuilder(BuildContext, ThingItem)`), so the app supplies the real
  image widget and a test supplies a colored box.
- Every tappable part gets a deterministic `ValueKey` from a documented prefix
  and the item id: `ValueKey('thing_row_$id')`. The class doc lists the
  prefixes.
- Colors, radii, and spacing come from the theme's tokens, never a literal.

**Why the keys:** an end-to-end script finds widgets by `#value_key`, and a
widget test taps the exact control rather than a label that changes with
state.

## 6. Rewrite the page as a composition

```dart
class ThingsPage extends StatefulWidget {
  const ThingsPage({super.key});
  @override
  State<ThingsPage> createState() => _ThingsPageState();
}

class _ThingsPageState extends State<ThingsPage> {
  final _controller = ThingsController();

  @override
  void initState() {
    super.initState();
    _controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => Scaffold(
        body: ThingList(
          items: _controller.items,
          isLoading: _controller.isLoading,
          error: _controller.error,
          selectedIds: _controller.selectedIds,
          onSelect: _controller.select,
          onDelete: _confirmDelete,
        ),
      ),
    );
  }
}
```

The `build` is package widgets arranged with plain Flutter layout (`Column`,
`Row`, `Expanded`, `Padding`, `SafeArea`) and nothing else. No sizing math, no
`MediaQuery` breakpoints, no `LayoutBuilder` branching, no private `_build*`
method that amounts to an unnamed widget.

**Why:** responsive behavior belongs in package layout widgets (a page
scaffold, a split view that collapses its sidebar under a breakpoint, a
section, a toolbar) so every page shares the same breakpoints and a layout fix
lands once. If the page needs a layout the package lacks, add the layout
widget to the package first, then compose.

What stays in the page: `Navigator` pushes, `showDialog`, `showModalBottomSheet`,
`ScaffoldMessenger` snack bars, and the sentence a user reads for an error. The
controller stores a raw failure; the page turns it into copy and hands the
string to the widget. **Why:** copy is product, not presentation, and a
package that composes sentences cannot be reused by a caller that words things
differently.

## 7. Test both halves

- **Controller:** plain `test()`, no `WidgetTester`. Construct it with fake
  functions and cover the load path, each action, and the error path. Assert
  that `notifyListeners` fired by counting through `addListener`.
- **Widgets:** layout tests at a narrow (360x640) and a wide (1280x800)
  viewport with `tester.takeException()` null, every callback fired once
  through its keyed element, and both light and dark. Use the
  `quark-widgets-widget-tests` skill; it has the full checklist and a template.

**Why in that order:** the controller test is where the logic lives and it
runs in milliseconds, so a broken action fails there with a readable stack
rather than three layers deep in a pumped tree.

## References

- [`references/controller_template.dart`](references/controller_template.dart)
  is a compiling `ChangeNotifier` with injectable service functions and the
  load, action, and error paths.
- [`references/before_after.md`](references/before_after.md) is a fetching list
  widget of about 60 lines, and the same thing afterward as a value type, a
  stateless widget, a controller, and a page, each shown in full.
