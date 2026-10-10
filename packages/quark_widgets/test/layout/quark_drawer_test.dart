import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The drawer draws a row only for a destination the caller offers, which is
/// how admin-only pages stay out of a non-admin's drawer (#1662).
void main() {
  Map<QuarkDrawerSection, void Function()> everyCallback(List<String> tapped) =>
      {
        for (final section in QuarkDrawerSection.values)
          section: () => tapped.add(section.name),
      };

  QuarkDrawer drawerWith(
    QuarkDrawerSection active,
    Map<QuarkDrawerSection, void Function()> callbacks,
  ) => QuarkDrawer(
    activeSection: active,
    onTapFiles: callbacks[QuarkDrawerSection.files],
    onTapPhotos: callbacks[QuarkDrawerSection.photos],
    onTapCalendar: callbacks[QuarkDrawerSection.calendar],
    onTapTrash: callbacks[QuarkDrawerSection.trash],
    onTapDocs: callbacks[QuarkDrawerSection.docs],
    onTapSheets: callbacks[QuarkDrawerSection.sheets],
    onTapSlides: callbacks[QuarkDrawerSection.slides],
    onTapBooks: callbacks[QuarkDrawerSection.books],
    onTapChat: callbacks[QuarkDrawerSection.chat],
    onTapSystem: callbacks[QuarkDrawerSection.system],
    onTapVault: callbacks[QuarkDrawerSection.vault],
    onTapUsers: callbacks[QuarkDrawerSection.users],
    onTapSettings: callbacks[QuarkDrawerSection.settings],
  );

  testBothViewports('lists every offered section and marks the active one', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      drawerWith(QuarkDrawerSection.photos, everyCallback([])),
      size: size,
    );

    final photos = tester.widget<ListTile>(
      find.byKey(const ValueKey('drawer_photos')),
    );
    expect(photos.selected, isTrue);
    final files = tester.widget<ListTile>(
      find.byKey(const ValueKey('drawer_files')),
    );
    expect(files.selected, isFalse);

    // Top to bottom: the narrow viewport is shorter than the drawer, and its
    // list only builds the rows that are scrolled into view.
    for (final label in [
      'Files',
      'Photos',
      'Calendar',
      'Docs',
      'Sheets',
      'Slides',
      'Books',
      'Chat',
      'Vault',
      'Manage',
      'Trash',
      'System',
      'Users',
      'Settings',
    ]) {
      await tester.scrollUntilVisible(find.text(label), 50);
      expect(find.text(label), findsOneWidget, reason: '$label is missing');
    }
    expect(tester.takeException(), isNull);
  });

  testBothViewports('calls back for the row that was tapped', (
    tester,
    size,
  ) async {
    final tapped = <String>[];
    await pumpAt(
      tester,
      drawerWith(QuarkDrawerSection.files, everyCallback(tapped)),
      size: size,
    );

    for (final section in QuarkDrawerSection.values) {
      // The narrow viewport is shorter than the drawer; it scrolls.
      final row = find.byKey(ValueKey('drawer_${section.name}'));
      await tester.scrollUntilVisible(row, 50);
      await tester.tap(row);
      await tester.pump();
    }

    expect(tapped, QuarkDrawerSection.values.map((s) => s.name).toList());
  });

  testBothViewports('draws no row for a section without a callback', (
    tester,
    size,
  ) async {
    final callbacks = everyCallback([])
      ..remove(QuarkDrawerSection.users)
      ..remove(QuarkDrawerSection.vault);
    await pumpAt(
      tester,
      drawerWith(QuarkDrawerSection.files, callbacks),
      size: size,
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('drawer_settings')),
      50,
    );
    expect(find.byKey(const ValueKey('drawer_users')), findsNothing);
    expect(find.text('Users'), findsNothing);
    expect(find.byKey(const ValueKey('drawer_vault')), findsNothing);
    expect(find.byKey(const ValueKey('drawer_settings')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('draws the users row once it is offered', (
    tester,
    size,
  ) async {
    final tapped = <String>[];
    await pumpAt(
      tester,
      QuarkDrawer(
        activeSection: QuarkDrawerSection.files,
        onTapUsers: () => tapped.add('users'),
      ),
      size: size,
    );

    await tester.tap(find.byKey(const ValueKey('drawer_users')));
    await tester.pump();

    expect(tapped, ['users']);
    expect(find.byKey(const ValueKey('drawer_files')), findsNothing);
  });

  /// #2046: the drawer was one flat list, so the pages a household opens every
  /// day sat between Trash and System. They lead now, and the pages for
  /// looking after the Quark follow under a "Manage" label.
  ///
  /// The keys of every child the drawer's list was handed, top to bottom. The
  /// list is lazy and the narrow viewport is shorter than the drawer, so this
  /// reads the delegate, not the screen.
  List<String> childKeys(WidgetTester tester) {
    final list = tester.widget<ListView>(find.byType(ListView));
    return [
      for (final child
          in (list.childrenDelegate as SliverChildListDelegate).children)
        if (child.key case final ValueKey<String> key) key.value,
    ];
  }

  const groupedOrder = [
    'drawer_files',
    'drawer_photos',
    'drawer_calendar',
    'drawer_docs',
    'drawer_sheets',
    'drawer_slides',
    'drawer_books',
    'drawer_chat',
    'drawer_vault',
    'drawer_group_manage',
    'drawer_trash',
    'drawer_system',
    'drawer_users',
    'drawer_settings',
  ];
  final manageLabel = find.byKey(const ValueKey('drawer_group_manage'));

  testBothViewports('leads with the household pages, then the Manage group', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      drawerWith(QuarkDrawerSection.files, everyCallback([])),
      size: size,
    );

    expect(childKeys(tester), groupedOrder);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('labels the Manage group only when it has a row', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      QuarkDrawer(activeSection: QuarkDrawerSection.files, onTapFiles: () {}),
      size: size,
    );
    expect(childKeys(tester), ['drawer_files']);
    expect(find.text('Manage'), findsNothing);

    await pumpAt(
      tester,
      QuarkDrawer(
        activeSection: QuarkDrawerSection.settings,
        onTapSettings: () {},
      ),
      size: size,
    );
    expect(childKeys(tester), ['drawer_group_manage', 'drawer_settings']);
    expect(find.text('Manage'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('the Manage label is a heading in line with the rows', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      drawerWith(QuarkDrawerSection.files, everyCallback([])),
      size: size,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('drawer_trash')),
      50,
    );

    final handle = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.text('Manage')),
      matchesSemantics(label: 'Manage', isHeader: true),
    );
    handle.dispose();
    expect(
      tester.getTopLeft(find.text('Manage')).dx,
      tester
          .getTopLeft(
            find.descendant(
              of: find.byKey(const ValueKey('drawer_trash')),
              matching: find.byType(Icon),
            ),
          )
          .dx,
    );
  });

  for (final themeColor in [QuarkThemeColor.magenta, QuarkThemeColor.lime]) {
    for (final brightness in Brightness.values) {
      testBothViewports(
        '${themeColor.name} ${brightness.name}: the Manage label is legible',
        (tester, size) async {
          await pumpAt(
            tester,
            QuarkDrawer(
              activeSection: QuarkDrawerSection.files,
              onTapFiles: () {},
              onTapSettings: () {},
            ),
            size: size,
            brightness: brightness,
            themeColor: themeColor,
          );

          final tokens = themeColor.tokensFor(brightness);
          final color = tester
              .renderObject<RenderParagraph>(find.text('Manage'))
              .text
              .style!
              .color!;
          expect(color, tokens.chromeSecondaryForeground);
          expect(
            contrastRatio(color, tokens.chrome),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            tester
                .widget<Divider>(
                  find.descendant(
                    of: manageLabel,
                    matching: find.byType(Divider),
                  ),
                )
                .color,
            tokens.chromeBorder,
          );
        },
      );
    }
  }

  // #1812: left-handed mode moves the drawer to the other edge. What is in the
  // drawer reads the way it always does.
  testBothViewports('left-handed mode leaves the groups as they are', (
    tester,
    size,
  ) async {
    Future<double> labelStart({required bool leftHanded}) async {
      await pumpAt(
        tester,
        QuarkHandedness(
          leftHanded: leftHanded,
          child: drawerWith(QuarkDrawerSection.files, everyCallback([])),
        ),
        size: size,
      );
      expect(childKeys(tester), groupedOrder);
      await tester.scrollUntilVisible(manageLabel, 50);
      expect(tester.takeException(), isNull);
      return tester.getTopLeft(find.text('Manage')).dx;
    }

    final rightHanded = await labelStart(leftHanded: false);
    expect(await labelStart(leftHanded: true), rightHanded);
  });

  testLargeText('the Manage label is not clipped', (tester, size) async {
    await pumpAt(
      tester,
      drawerWith(QuarkDrawerSection.files, everyCallback([])),
      size: size,
    );
    await tester.scrollUntilVisible(manageLabel, 50);

    expect(find.text('Manage'), findsOneWidget);
    expectNoClippedText(tester);
    expect(tester.takeException(), isNull);
  });

  for (final (label, brightness) in [
    ('dark', Brightness.dark),
    ('light', Brightness.light),
  ]) {
    testWidgets('$label: lays out without an exception', (tester) async {
      await pumpAt(
        tester,
        drawerWith(QuarkDrawerSection.users, everyCallback([])),
        brightness: brightness,
      );
      expect(tester.takeException(), isNull);
    });
  }

  /// #2033: with more than one Quark saved, nothing in the signed-in app said
  /// which one was on screen, so an upload could land on the wrong device
  /// without a single hint beforehand.
  testBothViewports('names the Quark it is signed in to', (tester, size) async {
    await pumpAt(
      tester,
      const QuarkDrawer(
        activeSection: QuarkDrawerSection.files,
        hosts: [HostItem(name: 'Cabin', address: 'cabin.local:8443')],
        activeHostIndex: 0,
      ),
      size: size,
    );

    expect(find.text('Cabin'), findsOneWidget);
    expect(find.text('cabin.local:8443'), findsOneWidget);
  });

  testWidgets('falls back to the product name when no host is passed', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const QuarkDrawer(activeSection: QuarkDrawerSection.files),
      size: narrowViewport,
    );

    expect(find.text('Quark'), findsOneWidget);
    expect(find.byKey(const ValueKey('drawer_host')), findsNothing);
  });

  testWidgets('a long nickname and address do not overflow a phone', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const QuarkDrawer(
        activeSection: QuarkDrawerSection.files,
        hosts: [
          HostItem(
            name: 'The Quark in the basement behind the water heater',
            address: 'https://quark-in-the-basement.home.local:8443',
          ),
          HostItem(name: 'Cabin', address: 'cabin.local'),
        ],
        activeHostIndex: 0,
        onSelectHost: _ignore,
      ),
      size: narrowViewport,
    );

    expect(tester.takeException(), isNull);
  });

  /// #2230: switching Quarks used to mean a trip to Settings.
  const hosts = [
    HostItem(name: 'Home', address: 'quark.home.local'),
    HostItem(name: 'Cabin', address: 'cabin.local:8443'),
  ];

  testBothViewports('a single Quark is a label, not a menu', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      QuarkDrawer(
        activeSection: QuarkDrawerSection.files,
        hosts: const [HostItem(name: 'Home', address: 'quark.home.local')],
        activeHostIndex: 0,
        onSelectHost: (_) => fail('no menu to select from'),
      ),
      size: size,
    );

    expect(find.text('Home'), findsOneWidget);
    expect(find.byKey(const ValueKey('drawer_host_header')), findsNothing);
    expect(find.byIcon(Icons.unfold_more_rounded), findsNothing);
  });

  testBothViewports('lists every Quark with the active one checked', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      QuarkDrawer(
        activeSection: QuarkDrawerSection.files,
        hosts: hosts,
        activeHostIndex: 1,
        onSelectHost: (_) {},
      ),
      size: size,
    );

    expect(find.byIcon(Icons.unfold_more_rounded), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('drawer_host_header')));
    await tester.pumpAndSettle();

    final home = tester.widget<CheckedPopupMenuItem<int>>(
      find.byKey(const ValueKey('drawer_host_0')),
    );
    final cabin = tester.widget<CheckedPopupMenuItem<int>>(
      find.byKey(const ValueKey('drawer_host_1')),
    );
    expect(home.checked, isFalse);
    expect(cabin.checked, isTrue);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('picking a Quark calls back with its index', (
    tester,
    size,
  ) async {
    final picked = <int>[];
    await pumpAt(
      tester,
      QuarkDrawer(
        activeSection: QuarkDrawerSection.files,
        hosts: hosts,
        activeHostIndex: 0,
        onSelectHost: picked.add,
      ),
      size: size,
    );

    await tester.tap(find.byKey(const ValueKey('drawer_host_header')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('drawer_host_1')));
    await tester.pumpAndSettle();

    expect(picked, [1]);
  });

  testBothViewports('the menu opens under the switcher icon', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      QuarkDrawer(
        activeSection: QuarkDrawerSection.files,
        hosts: hosts,
        activeHostIndex: 0,
        onSelectHost: (_) {},
      ),
      size: size,
    );

    final icon = tester.getRect(find.byIcon(Icons.unfold_more_rounded));
    await tester.tap(find.byKey(const ValueKey('drawer_host_header')));
    await tester.pumpAndSettle();

    final menu = tester.getRect(
      find
          .ancestor(
            of: find.byKey(const ValueKey('drawer_host_0')),
            matching: find.byType(Material),
          )
          .last,
    );
    expect(menu.right, closeTo(icon.right, 1));
    expect(menu.top, greaterThanOrEqualTo(icon.bottom));
    expect(find.byTooltip('Switch Quark'), findsNothing);
  });

  testBothViewports('marks the betas and hides each when not offered', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      drawerWith(QuarkDrawerSection.files, everyCallback([])),
      size: size,
    );
    for (final section in [
      QuarkDrawerSection.calendar,
      QuarkDrawerSection.slides,
      QuarkDrawerSection.chat,
    ]) {
      final row = find.byKey(ValueKey('drawer_${section.name}'));
      await tester.scrollUntilVisible(row, 50);
      expect(
        find.descendant(of: row, matching: find.byType(QuarkBetaBadge)),
        findsOneWidget,
        reason: section.name,
      );
    }

    for (final section in [
      QuarkDrawerSection.calendar,
      QuarkDrawerSection.chat,
    ]) {
      await pumpAt(
        tester,
        drawerWith(
          QuarkDrawerSection.files,
          everyCallback([])..remove(section),
        ),
        size: size,
      );
      expect(
        find.byKey(ValueKey('drawer_${section.name}'), skipOffstage: false),
        findsNothing,
        reason: section.name,
      );
    }
    expect(tester.takeException(), isNull);
  });

  // #2740: the drawer is colored chrome under a derived theme color.
  for (final brightness in Brightness.values) {
    testBothViewports('${brightness.name}: the rows wear the chrome colors', (
      tester,
      size,
    ) async {
      await pumpAt(
        tester,
        QuarkDrawer(
          activeSection: QuarkDrawerSection.photos,
          onTapFiles: () {},
          onTapPhotos: () {},
          onTapCalendar: () {},
        ),
        size: size,
        brightness: brightness,
        themeColor: QuarkThemeColor.magenta,
      );

      final tokens = QuarkThemeColor.magenta.tokensFor(brightness);
      Color textColor(String label) => tester
          .renderObject<RenderParagraph>(find.text(label))
          .text
          .style!
          .color!;
      Color iconColor(String key) => IconTheme.of(
        tester.element(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(Icon),
          ),
        ),
      ).color!;

      expect(
        tester
            .widget<Material>(
              find
                  .descendant(
                    of: find.byType(Drawer),
                    matching: find.byType(Material),
                  )
                  .first,
            )
            .color,
        tokens.chrome,
      );
      expect(textColor('Files'), tokens.chromeForeground);
      expect(iconColor('drawer_files'), tokens.chromeSecondaryForeground);
      // The active row and the beta badge are the accent as chrome draws it.
      expect(textColor('Photos'), tokens.chromePrimary);
      expect(iconColor('drawer_photos'), tokens.chromePrimary);
      expect(textColor('Beta'), tokens.chromePrimary);
      final header = tester.widget<DrawerHeader>(find.byType(DrawerHeader));
      expect((header.decoration! as BoxDecoration).color, tokens.chromePrimary);
      expect(tester.takeException(), isNull);
    });
  }

  // The header is filled with the accent as chrome draws it, so everything
  // on it has to be the accent's foreground, whichever way that flipped.
  for (final themeColor in [QuarkThemeColor.blue, QuarkThemeColor.lime]) {
    for (final brightness in Brightness.values) {
      testBothViewports(
        '${themeColor.name} ${brightness.name}: the header text is legible',
        (tester, size) async {
          await pumpAt(
            tester,
            QuarkDrawer(
              activeSection: QuarkDrawerSection.files,
              hosts: const [
                HostItem(name: 'Home Quark', address: 'quark.local'),
                HostItem(name: 'Office', address: 'office.local'),
              ],
              activeHostIndex: 0,
              onSelectHost: (_) {},
              onTapFiles: () {},
            ),
            size: size,
            brightness: brightness,
            themeColor: themeColor,
          );

          final tokens = themeColor.tokensFor(brightness);
          final header = tester.widget<DrawerHeader>(find.byType(DrawerHeader));
          final fill = (header.decoration! as BoxDecoration).color!;
          expect(fill, tokens.chromePrimary);

          final inHeader = find.descendant(
            of: find.byType(DrawerHeader),
            matching: find.byType(RichText),
          );
          final paragraphs = tester.renderObjectList<RenderParagraph>(inHeader);
          // "Quark", the host name, its address, and the switcher glyph.
          expect(paragraphs, hasLength(4));
          for (final paragraph in paragraphs) {
            // Muted lines are the foreground at reduced alpha, so measure
            // what is painted: the color over the fill.
            final painted = Color.alphaBlend(
              paragraph.text.style!.color!,
              fill,
            );
            expect(
              contrastRatio(painted, fill),
              greaterThanOrEqualTo(4.5),
              reason: '"${paragraph.text.toPlainText()}"',
            );
          }
        },
      );
    }
  }
}

void _ignore(int _) {}
