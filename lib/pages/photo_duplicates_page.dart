import 'package:flutter/material.dart';
import 'package:quark/controllers/duplicates_controller.dart';
import 'package:quark/utils/auto_refresh_mixin.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_browser_dialog_utils.dart';
import 'package:quark/widgets/photos/photo_thumbnail.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Photos that duplicate each other, for picking which copies to keep
/// (#1666). A drill-down from Photos at `/photos/duplicates`, so it has a
/// back button rather than the drawer. When a picture is saved in several
/// formats, the bar offers which format to keep.
class PhotoDuplicatesPage extends StatefulWidget {
  const PhotoDuplicatesPage({super.key, this.controller});

  /// Overrides the controller, for a test. Null uses the real services.
  final DuplicatesController? controller;

  @override
  State<PhotoDuplicatesPage> createState() => _PhotoDuplicatesPageState();
}

class _PhotoDuplicatesPageState extends State<PhotoDuplicatesPage>
    with WidgetsBindingObserver, AutoRefreshMixin {
  late final DuplicatesController _controller =
      widget.controller ?? DuplicatesController();

  @override
  Future<void> refresh() => _controller.load();

  Future<void> _deleteSelected() async {
    final count = _controller.selectedIds.length;
    final confirmed = await confirmDelete(
      context,
      count == 1 ? '1 photo' : '$count photos',
    );
    if (confirmed != true || !mounted) return;
    final failed = await _controller.deleteSelected();
    if (!mounted || failed == 0) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          Errors.couldNot('delete $failed ${failed == 1 ? 'photo' : 'photos'}'),
        ),
      ),
    );
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final error = _controller.error;
        final formats = _controller.formats;
        return Scaffold(
          key: const ValueKey('photo_duplicates_page'),
          appBar: AppBar(
            title: const Text('Duplicates'),
            actions: [
              if (formats.isNotEmpty)
                DuplicateFormatButton(
                  formats: formats,
                  preferred: _controller.preferredFormat,
                  onChanged: _controller.setPreferredFormat,
                ),
            ],
          ),
          body: DuplicateGroupList(
            groups: _controller.groups,
            selectedIds: _controller.selectedIds,
            isLoading: _controller.isLoading,
            isDeleting: _controller.isDeleting,
            error: error == null
                ? null
                : Errors.message(error, 'find duplicate photos'),
            thumbnailBuilder: (context, photo) =>
                PhotoThumbnail(url: _controller.thumbnailUrl(photo.id)),
            onToggle: _controller.toggle,
            onDeleteSelected: _deleteSelected,
          ),
        );
      },
    );
  }
}
