import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quark/controllers/users_controller.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/utils/auto_refresh_mixin.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/layout/app_drawer.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The admin-only Users page (#1662): account requests waiting for approval,
/// every account on the Quark, and whether the Quark takes requests at all.
///
/// The router only opens it for an admin, and the Quark refuses its requests
/// from anyone else.
class UsersPage extends StatefulWidget {
  const UsersPage({super.key});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage>
    with WidgetsBindingObserver, AutoRefreshMixin {
  final _controller = UsersController(
    selfUsername: AppSettings.instance.username,
  );
  StreamSubscription<FileEvent>? _eventSub;

  @override
  void initState() {
    super.initState();
    EventsService.instance.start();
    // Another admin's change, or a new request, from any client, shows up here
    // without a reload.
    _eventSub = EventsService.instance.events.listen((event) {
      if (event.kind == 'account_changed' || event.kind == 'access_changed') {
        manualRefresh();
      }
    });
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Future<void> refresh() => _controller.load();

  /// Waits for [action] and says why it failed, if it did. [failure] is the
  /// action phrase for [Errors.message].
  Future<void> _report(Future<Object?> action, String failure) async {
    final error = await action;
    if (error == null || !mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(Errors.message(error, failure))));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final c = _controller;
        final loadError = c.error;
        final isLoading = !c.hasLoaded && loadError == null;
        // A failed refresh keeps the last good rows on screen.
        final shownError = c.hasLoaded || loadError == null
            ? null
            : Errors.message(loadError, 'load the accounts');
        final accessRequestsEnabled = c.accessRequestsEnabled;
        return QuarkPageScaffold(
          title: 'Users',
          icon: QuarkIcons.person_outline,
          actions: [
            RefreshIconButton(
              isRefreshing: isRefreshing,
              onPressed: manualRefresh,
            ),
            const AppThemeToggle(),
          ],
          drawer: const AppDrawer(activeSection: QuarkDrawerSection.users),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              QuarkSection(
                title: 'Requests',
                child: PendingRequestList(
                  requests: c.pending,
                  isLoading: isLoading,
                  error: shownError,
                  busyUsernames: c.busyUsernames,
                  onApprove: (username) => _report(
                    c.approve(username),
                    "approve $username's request",
                  ),
                  onDeny: (username) =>
                      _report(c.deny(username), "deny $username's request"),
                ),
              ),
              if (accessRequestsEnabled != null)
                AccessRequestsTile(
                  enabled: accessRequestsEnabled,
                  isBusy: c.isSavingAccessRequests,
                  onChanged: (enabled) => _report(
                    c.setAccessRequestsEnabled(enabled),
                    enabled
                        ? 'turn account requests on'
                        : 'turn account requests off',
                  ),
                ),
              const SizedBox(height: 24),
              QuarkSection(
                title: 'Accounts',
                child: UserList(
                  users: c.accounts,
                  selfUsername: c.selfUsername,
                  isLoading: isLoading,
                  error: shownError,
                  busyUsernames: c.busyUsernames,
                  onPromote: (username) =>
                      _report(c.promote(username), 'make $username an admin'),
                  onDemote: (username) => _report(
                    c.demote(username),
                    'remove $username as an admin',
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
