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
  /// Creates the host for [selectedCount] photos.
  const AlbumPickerSheetHost({
    required this.selectedCount,
    required this.loadAlbums,
    super.key,
  });

  /// Shows the picker and answers with the album chosen, or null.
  static Future<AlbumItem?> show(
    BuildContext context, {
    required int selectedCount,
    required Future<List<AlbumItem>> Function() loadAlbums,
  }) {
    return showModalBottomSheet<AlbumItem>(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(QuarkColors.radiusLg),
      ),
      builder: (_) => AlbumPickerSheetHost(
        selectedCount: selectedCount,
        loadAlbums: loadAlbums,
      ),
    );
  }

  /// How many photos are being added.
  final int selectedCount;

  /// Fetches the album tree.
  final Future<List<AlbumItem>> Function() loadAlbums;

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

  @override
  Widget build(BuildContext context) {
    return AlbumPickerSheet(
      selectedCount: widget.selectedCount,
      albums: _albums,
      isLoading: _loading,
      error: _error,
      onPicked: (album) => Navigator.of(context).pop(album),
      onRetry: _load,
    );
  }
}
