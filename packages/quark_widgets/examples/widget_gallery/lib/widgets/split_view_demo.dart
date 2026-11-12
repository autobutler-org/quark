import 'package:material_ui/material_ui.dart';
import 'package:quark_widgets/quark_widgets.dart';

import 'demo_album_sidebar.dart';
import 'framed_viewport.dart';

/// Shows [QuarkSplitView] in both of its layouts at once, and holds the
/// `isSidebarOpen` flag the widget refuses to hold, which is the point of the
/// example: the gallery is the caller.
class SplitViewDemo extends StatefulWidget {
  /// Creates the example, logging every callback through [log].
  const SplitViewDemo({required this.log, super.key});

  /// The gallery's event panel.
  final void Function(String event) log;

  @override
  State<SplitViewDemo> createState() => _SplitViewDemoState();
}

class _SplitViewDemoState extends State<SplitViewDemo> {
  bool _sidebarOpen = true;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final theme = Theme.of(context);
    final slivers = [
      SliverList.builder(
        itemCount: 20,
        itemBuilder: (context, index) =>
            ListTile(dense: true, title: Text('Photo ${index + 1}')),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Above the breakpoint: the sidebar is a pane',
          style: theme.textTheme.titleSmall,
        ),
        SizedBox(height: tokens.spacingSm),
        FramedViewport(
          width: 1000,
          child: QuarkSplitView(
            sidebar: const DemoAlbumSidebar(),
            slivers: slivers,
          ),
        ),
        SizedBox(height: tokens.spacingLg),
        Text(
          'Below it: the sidebar stacks above the content, and the toggle '
          'reports out',
          style: theme.textTheme.titleSmall,
        ),
        SizedBox(height: tokens.spacingSm),
        FramedViewport(
          width: 360,
          child: QuarkSplitView(
            isSidebarOpen: _sidebarOpen,
            onToggleSidebar: () {
              widget.log('QuarkSplitView.onToggleSidebar');
              setState(() => _sidebarOpen = !_sidebarOpen);
            },
            sidebar: const DemoAlbumSidebar(),
            slivers: slivers,
          ),
        ),
      ],
    );
  }
}
