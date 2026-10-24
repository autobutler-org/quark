import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:quark/controllers/photo_index_controller.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The photo library index status above duplicate results (#3556), for an
/// admin: whether the results may be incomplete, pause and resume, and the
/// files that could not be read.
///
/// The Quark answers the status to admins only, and its
/// `photo_index_changed` event carries nothing, so a non-admin has no way to
/// learn whether indexing is still running: for them this shows nothing.
/// Nothing is fetched until the account is an admin. It is coupled to the
/// app because it reads [AppSettings.isAdmin] and words errors with
/// [Errors].
class PhotoIndexStatusSection extends StatefulWidget {
  /// Creates the section.
  const PhotoIndexStatusSection({super.key, this.controller});

  /// Overrides the controller, for a test. Null uses the real services.
  final PhotoIndexController? controller;

  @override
  State<PhotoIndexStatusSection> createState() =>
      _PhotoIndexStatusSectionState();
}

class _PhotoIndexStatusSectionState extends State<PhotoIndexStatusSection> {
  late final PhotoIndexController _controller =
      widget.controller ?? PhotoIndexController();
  final ValueListenable<bool> _isAdmin = AppSettings.instance.isAdmin;

  @override
  void initState() {
    super.initState();
    _isAdmin.addListener(_onAdminChanged);
    _onAdminChanged();
  }

  void _onAdminChanged() {
    if (_isAdmin.value) _controller.start();
  }

  @override
  void dispose() {
    _isAdmin.removeListener(_onAdminChanged);
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _isAdmin,
      builder: (context, isAdmin, _) => ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final status = _controller.status;
          final error = _controller.error;
          if (!isAdmin || _controller.isHidden) return const SizedBox.shrink();
          final spacing = QuarkTokens.of(context).spacingMd;
          return Padding(
            padding: EdgeInsets.fromLTRB(spacing, spacing, spacing, 0),
            child: PhotoIndexStatusPanel(
              total: status?.total ?? 0,
              hashed: status?.hashed ?? 0,
              datesRead: status?.datesRead ?? 0,
              failed: status?.failed ?? 0,
              isRunning: status?.running ?? false,
              isPaused: status?.paused ?? false,
              lastRunAt: status?.lastRunAt,
              failures: _controller.failures,
              showFailures: _controller.showFailures,
              onToggleFailures: _controller.toggleFailures,
              onPause: _controller.pause,
              onResume: _controller.resume,
              isChanging: _controller.isChanging,
              isLoading: _controller.isLoading,
              error: error == null
                  ? null
                  : Errors.message(error, _controller.errorAction),
            ),
          );
        },
      ),
    );
  }
}
