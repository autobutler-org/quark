import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/image_viewer/desktop_body.dart';
import 'package:quark/widgets/image_viewer/metadata_sidebar.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../support/tap_target_guidelines.dart' show setViewport;

/// The photo viewer's metadata sidebar resizes from its inner edge and hides
/// when dragged below its min width, like every other sidebar (#4294).
void main() {
  const handle = ValueKey('resizable_pane_handle_photo_viewer');

  Future<void> pumpBody(WidgetTester tester, List<String> events) async {
    setViewport(tester, const Size(1280, 800));
    var width = DesktopBody.defaultSidebarWidth;
    var open = true;
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => DesktopBody(
              photoArea: const SizedBox.expand(),
              sidebarOpen: open,
              sidebarWidth: width,
              onSidebarWidthChanged: (w) => setState(() {
                events.add('width ${w.round()}');
                width = w;
              }),
              onSidebarOpenChanged: (o) => setState(() {
                events.add('open $o');
                open = o;
              }),
              name: 'photo.jpg',
              metadata: null,
              loading: false,
              onAlbumTap: (_) {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('dragging the edge toward the photo widens the sidebar', (
    tester,
  ) async {
    final events = <String>[];
    await pumpBody(tester, events);

    await tester.drag(find.byKey(handle), const Offset(-60, 0));
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byType(MetadataSidebar)).width,
      DesktopBody.defaultSidebarWidth + 60,
    );
    expect(
      events.last,
      'width ${(DesktopBody.defaultSidebarWidth + 60).round()}',
    );
  });

  testWidgets('dragging it below the min width hides the sidebar', (
    tester,
  ) async {
    final events = <String>[];
    await pumpBody(tester, events);

    await tester.drag(find.byKey(handle), const Offset(260, 0));
    await tester.pumpAndSettle();

    expect(events, contains('open false'));
    expect(find.byType(MetadataSidebar), findsNothing);
  });
}
