import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/slides_controller.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/router.dart';
import 'package:quark/utils/auto_refresh_mixin.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_browser_dialog_utils.dart';
import 'package:quark/utils/rename_doc_sheet.dart';
import 'package:quark/widgets/layout/app_drawer.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:quark/widgets/slides/slides_body.dart';
import 'package:quark/widgets/slides/slides_search_bar.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The Slides page: the user's `.qslide` presentations, a search over their
/// names and contents, and a way to start a new one (#1161).
class SlidesPage extends StatefulWidget {
  /// Creates the page; [controller] is for tests, which pass one with fake
  /// services.
  const SlidesPage({this.controller, super.key});

  /// The page's state; the real services when null.
  final SlidesController? controller;

  @override
  State<SlidesPage> createState() => _SlidesPageState();
}

class _SlidesPageState extends State<SlidesPage>
    with WidgetsBindingObserver, AutoRefreshMixin {
  late final SlidesController _controller =
      widget.controller ?? SlidesController();
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.addListener(() => _controller.setQuery(_search.text));
  }

  @override
  void dispose() {
    _search.dispose();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Future<void> refresh() => _controller.refresh();

  void _open(FileNode node) =>
      context.go(AppRoutes.slideFile(node.apiPath, serial: node.deviceSerial));

  Future<void> _rename(FileNode node) async {
    final renamed = await renameDocOrSheet(
      context,
      node,
      siblings: _controller.files,
    );
    if (renamed != null) manualRefresh();
  }

  Future<void> _create() async {
    final name = await promptForNewFileName(
      context,
      title: 'New presentation',
      hintText: 'Presentation name',
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    try {
      final path = await _controller.create(name.trim());
      if (mounted) context.go(AppRoutes.slideFile(path));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Errors.upload(e, 'create the presentation'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: QuarkAppBar(
        label: 'Slides',
        icon: QuarkIcons.slideshow_outlined,
        onRefresh: manualRefresh,
        isRefreshing: isRefreshing,
        actions: [
          QuarkBarChip(
            key: const ValueKey('slides_new'),
            icon: QuarkIcons.add_rounded,
            label: 'New presentation',
            tooltip: 'New presentation',
            onPressed: _create,
          ),
          const AppThemeToggle(),
        ],
      ),
      drawer: const AppDrawer(activeSection: QuarkDrawerSection.slides),
      body: Column(
        children: [
          SlidesSearchBar(controller: _search),
          Expanded(
            child: ListenableBuilder(
              listenable: _controller,
              builder: (context, _) => SlidesBody(
                loading: isInitialLoad && _controller.files.isEmpty,
                error: _controller.error,
                files: _controller.filtered,
                contentResults: _controller.contentResults,
                contentSearching: _controller.contentSearching,
                searchQuery: _controller.query,
                onRetry: manualRefresh,
                onCreateNew: _create,
                onOpen: _open,
                onRename: _rename,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
