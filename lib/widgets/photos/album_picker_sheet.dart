import 'package:flutter/material.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Opens the package's [AlbumPickerSheet] and feeds it albums from
/// [loadAlbums], retrying on request.
///
/// The load is injected rather than called here, so this widget holds the
/// sheet's loading state without knowing a service exists. Pops with the
/// picked album, or null when dismissed.
class AlbumPickerSheetHost extends StatefulWidget {
  /// Creates the host over the albums [loadAlbums] fetches.
  const AlbumPickerSheetHost({
    required this.loadAlbums,
    this.onCreateAlbum,
    super.key,
  });

  /// Shows the picker for [selectedCount] photos and answers with the album
  /// chosen, or null.
  static Future<AlbumItem?> show(
    BuildContext context, {
    required int selectedCount,
    required Future<List<AlbumItem>> Function() loadAlbums,
    Future<AlbumItem?> Function()? onCreateAlbum,
  }) {
    return showQuarkSheet<AlbumItem>(
      context,
      title:
          'Add $selectedCount ${selectedCount == 1 ? 'photo' : 'photos'} '
          'to...',
      builder: (_) => AlbumPickerSheetHost(
        loadAlbums: loadAlbums,
        onCreateAlbum: onCreateAlbum,
      ),
    );
  }

  /// Fetches the album tree.
  final Future<List<AlbumItem>> Function() loadAlbums;

  /// Names and creates an album, answering with it — or null if the user
  /// backed out. Null hides the empty state's create action (#2041).
  final Future<AlbumItem?> Function()? onCreateAlbum;

  @override
  State<AlbumPickerSheetHost> createState() => _AlbumPickerSheetHostState();
}

class _AlbumPickerSheetHostState extends State<AlbumPickerSheetHost> {
  List<AlbumItem> _albums = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final albums = await widget.loadAlbums();
      if (!mounted) return;
      setState(() {
        _albums = albums;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = Errors.message(e, 'load your albums');
      });
    }
  }

  /// Makes an album and picks it, so the selection the user built lands in it
  /// without leaving the sheet (#2041).
  Future<void> _createAndPick() async {
    final album = await widget.onCreateAlbum!();
    if (album == null || !mounted) return;
    Navigator.of(context).pop(album);
  }

  @override
  Widget build(BuildContext context) {
    return AlbumPickerSheet(
      albums: _albums,
      isLoading: _loading,
      error: _error,
      onPicked: (album) => Navigator.of(context).pop(album),
      onRetry: _load,
      onCreateAlbum: widget.onCreateAlbum == null ? null : _createAndPick,
    );
  }
}
