import 'package:flutter/material.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/services/storage_service.dart' show StorageDevice;
import 'package:quark/widgets/slides/slides_error_view.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Everything under the Books app bar: the load state, the error or
/// disconnected view, the empty state, or one row per book with its folder
/// and size (#1678).
///
/// Key prefixes: `book_tile_<path>` on each row, where the path is the book's
/// path under the files root, and [SlidesErrorView]'s `slides_retry` on the
/// retry button.
class BooksBody extends StatelessWidget {
  /// Shows [books], or the state standing in for them.
  const BooksBody({
    required this.loading,
    required this.error,
    required this.books,
    required this.onRetry,
    required this.onOpen,
    super.key,
  });

  /// Whether the first listing is still on its way, with nothing to show.
  final bool loading;

  /// The thrown object from the last refresh, not its message —
  /// [SlidesErrorView] decides what it means.
  final Object? error;

  /// The books to list, in order.
  final List<FileNode> books;

  /// Called by the error view's retry button.
  final VoidCallback onRetry;

  /// Called with the book tapped.
  final ValueChanged<FileNode> onOpen;

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: QuarkLoader());
    final error = this.error;
    if (error != null) {
      return SlidesErrorView(
        error: error,
        action: 'load your books',
        onRetry: onRetry,
      );
    }
    if (books.isEmpty) {
      return const EmptyStateWidget(
        icon: QuarkIcons.menu_book_outlined,
        headline: 'No books yet',
        subtext: 'PDF and EPUB files you add to Files show up here.',
      );
    }
    return ListView.builder(
      itemCount: books.length,
      itemBuilder: (context, i) {
        final book = books[i];
        final slash = book.apiPath.lastIndexOf('/');
        final folder = slash < 0 ? '' : book.apiPath.substring(0, slash);
        return ListTile(
          key: ValueKey('book_tile_${book.apiPath}'),
          leading: QuarkFileIcon(name: book.name, isDir: false, size: 24),
          title: Text(book.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            [
              if (folder.isNotEmpty) folder,
              StorageDevice.formatBytes(book.size),
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => onOpen(book),
        );
      },
    );
  }
}
