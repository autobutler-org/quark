import 'package:flutter/material.dart';
import 'package:quark/controllers/jobs_controller.dart';
import 'package:quark/utils/auto_refresh_mixin.dart';
import 'package:quark/widgets/layout/app_drawer.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Long-running jobs on the Quark: conversions and anything else on the job
/// queue, with Cancel and Retry.
class JobsPage extends StatefulWidget {
  /// Creates the page over [controller], the app's one [JobsController] unless
  /// a test passes its own.
  JobsPage({JobsController? controller, super.key})
    : controller = controller ?? JobsController.instance;

  /// Where the jobs come from. Shared with the rest of the app, so the page
  /// never disposes it.
  final JobsController controller;

  @override
  State<JobsPage> createState() => _JobsPageState();
}

class _JobsPageState extends State<JobsPage>
    with WidgetsBindingObserver, AutoRefreshMixin {
  @override
  Future<void> refresh() => widget.controller.load();

  Future<void> _report(Future<String?> action) async {
    final message = await action;
    if (message == null || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => QuarkPageScaffold(
        title: 'Jobs',
        icon: QuarkIcons.pending_actions_outlined,
        actions: [
          RefreshIconButton(
            isRefreshing: isRefreshing,
            onPressed: manualRefresh,
          ),
          const AppThemeToggle(),
        ],
        drawer: const AppDrawer(activeSection: QuarkDrawerSection.jobs),
        body: JobList(
          items: controller.items,
          isLoading: isInitialLoad || controller.isLoading,
          error: controller.error,
          onCancel: (id) => _report(controller.cancel(id)),
          onRetry: (id) => _report(controller.retry(id)),
        ),
      ),
    );
  }
}
