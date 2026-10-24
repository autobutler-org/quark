import 'package:flutter/material.dart';
import 'package:quark/controllers/jobs_controller.dart';
import 'package:quark/utils/auto_refresh_mixin.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The System page's Jobs tab: long-running jobs on the Quark, conversions
/// and anything else on the job queue, with Cancel and Retry.
class JobsTab extends StatefulWidget {
  /// Creates the tab over the app's one [JobsController], which is shared
  /// with the rest of the app, so the tab never disposes it.
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
  Future<void> refresh() => JobsController.instance.load();

  Future<void> _report(Future<String?> action) async {
    final message = await action;
    if (message == null || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final controller = JobsController.instance;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => JobList(
        items: controller.items,
        isLoading: isInitialLoad || controller.isLoading,
        error: controller.error,
        onCancel: (id) => _report(controller.cancel(id)),
        onRetry: (id) => _report(controller.retry(id)),
      ),
    );
  }
}
