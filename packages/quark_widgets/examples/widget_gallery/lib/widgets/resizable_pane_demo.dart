import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import 'demo_album_sidebar.dart';
import 'framed_viewport.dart';

/// Shows [QuarkResizablePane] beside some content, holding the width and the
/// collapsed flag the widget refuses to hold, which is the point of the
/// example: the gallery is the caller. A button outside the pane reopens it,
/// the way a page puts its show/hide button in its own header.
class ResizablePaneDemo extends StatefulWidget {
  /// Creates the example, logging every callback through [log].
  const ResizablePaneDemo({required this.log, super.key});

  /// The gallery's event panel.
  final void Function(String event) log;

  @override
  State<ResizablePaneDemo> createState() => _ResizablePaneDemoState();
}

class _ResizablePaneDemoState extends State<ResizablePaneDemo> {
  double _width = 240;
  bool _collapsed = false;

  void _setCollapsed(bool collapsed) {
    widget.log('QuarkResizablePane.onCollapsedChanged($collapsed)');
    setState(() => _collapsed = collapsed);
  }

  @override
  Widget build(BuildContext context) {
    return FramedViewport(
      width: 1000,
      child: Row(
        children: [
          QuarkResizablePane(
            id: 'demo',
            semanticLabel: 'Resize albums',
            width: _width,
            defaultWidth: 240,
            isCollapsed: _collapsed,
            onWidthChanged: (width) {
              widget.log('QuarkResizablePane.onWidthChanged(${width.round()})');
              setState(() => _width = width);
            },
            onCollapsedChanged: _setCollapsed,
            child: const DemoAlbumSidebar(),
          ),
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.topStart,
              child: QuarkBarIconButton(
                icon: _collapsed ? QuarkIcons.menu : QuarkIcons.menu_open,
                tooltip: _collapsed ? 'Show albums' : 'Hide albums',
                onPressed: () => _setCollapsed(!_collapsed),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
