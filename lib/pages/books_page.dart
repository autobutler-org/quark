import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/books_controller.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/router.dart';
import 'package:quark/utils/auto_refresh_mixin.dart';
import 'package:quark/widgets/books/books_body.dart';
import 'package:quark/widgets/layout/app_drawer.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The Books page: every PDF and EPUB on the Quark in one list, each opening
/// in the file viewer Files uses (#1678).
class BooksPage extends StatefulWidget {
  /// Creates the page; [controller] is for tests, which pass one with a fake
  /// service.
  const BooksPage({this.controller, super.key});

  /// The page's state; the real service when null.
  final BooksController? controller;

  @override
  State<BooksPage> createState() => _BooksPageState();
}

class _BooksPageState extends State<BooksPage>
    with WidgetsBindingObserver, AutoRefreshMixin {
  late final BooksController _controller =
      widget.controller ?? BooksController();

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Future<void> refresh() => _controller.refresh();

  void _open(FileNode book) =>
      context.go(AppRoutes.viewFilePath(book.apiPath, from: AppRoutes.books));

  @override
  Widget build(BuildContext context) {
    return QuarkPageScaffold(
      title: 'Books',
      icon: QuarkIcons.menu_book_outlined,
      onRefresh: manualRefresh,
      isRefreshing: isRefreshing,
      actions: const [AppThemeToggle()],
      drawer: const AppDrawer(activeSection: QuarkDrawerSection.books),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => BooksBody(
          loading: isInitialLoad && _controller.books.isEmpty,
          error: _controller.error,
          books: _controller.books,
          onRetry: manualRefresh,
          onOpen: _open,
        ),
      ),
    );
  }
}
