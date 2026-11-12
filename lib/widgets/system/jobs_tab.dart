import 'package:material_ui/material_ui.dart';
import 'package:quark/controllers/jobs_controller.dart';
import 'package:quark/controllers/upload_sessions_controller.dart';
import 'package:quark/utils/auto_refresh_mixin.dart';
import 'package:quark/utils/file_browser_dialog_utils.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The System page's Jobs tab: the account's uploads from any device, with
/// their progress (#3972), then long-running jobs on the Quark, conversions
/// and anything else on the job queue, with Cancel and Retry.
class JobsTab extends StatefulWidget {
  /// Creates the tab over the app's one [JobsController] and
  /// [UploadSessionsController], which are shared with the rest of the app,
  /// so the tab never disposes them.
  const JobsTab({this.onRefreshingChanged, super.key});

  /// Called with whether a refresh is in flight whenever that changes, so
  /// the page's app bar can show it.
  final ValueChanged<bool>? onRefreshingChanged;

  @override
  State<JobsTab> createState() => _JobsTabState();
}

class _JobsTabState extends State<JobsTab>
    with WidgetsBindingObserver, AutoRefreshMixin {
  @override
  void didChangeRefreshing() => widget.onRefreshingChanged?.call(isRefreshing);

  @override
  Future<void> refresh() => Future.wait([
    JobsController.instance.load(),
    UploadSessionsController.instance.load(),
  ]);

  Future<void> _report(Future<String?> action) async {
    final message = await action;
    if (message == null || !mounted) return;
    showMessage(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final controller = JobsController.instance;
    final uploads = UploadSessionsController.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([controller, uploads]),
      builder: (context, _) => JobList(
        uploads: uploads.items,
        items: controller.items,
        isLoading: isInitialLoad || controller.isLoading || uploads.isLoading,
        error: controller.error ?? uploads.error,
        onCancelUpload: (id) => _report(uploads.cancel(id)),
        onCancel: (id) => _report(controller.cancel(id)),
        onRetry: (id) => _report(controller.retry(id)),
      ),
    );
  }
}
