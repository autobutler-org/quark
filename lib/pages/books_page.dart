import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/books_controller.dart';
import 'package:quark/controllers/file_browser_events_controller.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/router.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/utils/auto_refresh_mixin.dart';
import 'package:quark/widgets/books/books_body.dart';
import 'package:quark/widgets/layout/app_drawer.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The Books page: every PDF and EPUB on the Quark in one list, each opening
/// in the file viewer Files uses, on the drive the book is on (#1678, #3712).
class BooksPage extends StatefulWidget {
  /// Creates the page; [controller] is for tests, which pass one with a fake
  /// service. [events] is the file-tree stream; null listens to the Quark's.
  const BooksPage({this.controller, this.events, super.key});

  /// The page's state; the real service when null.
  final BooksController? controller;

  /// File-tree events that refresh the list. Null follows [EventsService].
  final Stream<FileEvent>? events;

  @override
  State<BooksPage> createState() => _BooksPageState();
}

class _BooksPageState extends State<BooksPage>
    with WidgetsBindingObserver, AutoRefreshMixin {
  late final BooksController _controller =
      widget.controller ?? BooksController();
  late final FileBrowserEventsController _events;

  @override
  void initState() {
    super.initState();
    if (widget.events == null) EventsService.instance.start();
    // Books lists every drive, so an upload, move, delete or restore anywhere
    // can change it. An empty folder means the whole tree to the events
    // controller, and its debounce keeps a burst to one refresh (#3712).
    _events = FileBrowserEventsController(
      events: widget.events,
      currentFolder: () => '',
      isBusy: () => false,
      onRefresh: manualRefresh,
    );
  }

  @override
  void dispose() {
    _events.dispose();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Future<void> refresh() => _controller.refresh();

  void _open(FileNode book) => context.go(
    AppRoutes.viewFilePath(
      book.apiPath,
      serial: book.deviceSerial,
      from: AppRoutes.books,
    ),
  );

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
