import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quark/controllers/groups_controller.dart';
import 'package:quark/controllers/users_controller.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/utils/auto_refresh_mixin.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/layout/app_drawer.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The admin-only Users page (#1662), in two tabs.
///
/// **Accounts**: account requests waiting for approval, every account on the
/// Quark with what an admin can do to each, adding an account, and whether
/// the Quark takes requests at all. **Groups** (#1910): the groups, creating,
/// renaming and deleting one, and who is in each.
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
  final _groups = GroupsController();
  late final Listenable _controllers = Listenable.merge([_controller, _groups]);
  StreamSubscription<FileEvent>? _eventSub;

  @override
  void initState() {
    super.initState();
    EventsService.instance.start();
    // Another admin's change to an account, a group or its members, or a new
    // request, from any client, shows up here without a reload.
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
    _groups.dispose();
    super.dispose();
  }

  @override
  Future<void> refresh() async {
    await Future.wait([_controller.load(), _groups.load()]);
  }

  /// Waits for [action] and says why it failed, if it did. [failure] is the
  /// action phrase for [Errors.message].
  Future<void> _report(Future<Object?> action, String failure) async {
    final error = await action;
    if (error == null || !mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(Errors.message(error, failure))));
  }

  /// Opens the add-account dialog. It rebuilds with the controller, so a
  /// refusal such as a taken name shows in the open dialog, and it closes
  /// once the account exists.
  Future<void> _openCreateDialog() async {
    _controller.clearCreateError();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => ListenableBuilder(
        listenable: _controller,
        builder: (dialogContext, _) {
          final error = _controller.createError;
          return CreateUserDialog(
            isSubmitting: _controller.isCreating,
            error: error == null ? null : Errors.message(error, 'add the user'),
            onCancel: () => Navigator.of(dialogContext).pop(),
            onSubmit: (input) async {
              final created = await _controller.create(input);
              if (created && dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
          );
        },
      ),
    );
  }

  /// Asks before deleting [username], then deletes (#1909).
  Future<void> _confirmDelete(String username) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => ConfirmDeleteDialog(
        title: 'Delete $username?',
        body:
            "$username won't be able to sign in again. The files they own "
            'stay on this Quark and become yours.',
        keyPrefix: 'delete_user',
        onConfirm: () => Navigator.of(dialogContext).pop(true),
        onCancel: () => Navigator.of(dialogContext).pop(false),
      ),
    );
    if (confirmed != true || !mounted) return;
    await _report(_controller.delete(username), 'delete $username');
  }

  /// Opens the dialog naming a new group, or renaming [group]. It rebuilds
  /// with the controller, so a refusal such as a taken name shows in the open
  /// dialog, and it closes once the name is saved.
  Future<void> _openGroupNameDialog([GroupItem? group]) async {
    _groups.clearSaveError();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => ListenableBuilder(
        listenable: _groups,
        builder: (dialogContext, _) {
          final error = _groups.saveError;
          return QuarkNameDialog(
            title: group == null ? 'New group' : 'Rename ${group.name}',
            label: 'Group name',
            submitLabel: group == null ? 'Create' : 'Rename',
            initialName: group?.name ?? '',
            maxLength: 64,
            isSubmitting: _groups.isSaving,
            error: error == null
                ? null
                : Errors.message(
                    error,
                    group == null ? 'create the group' : 'rename the group',
                  ),
            onCancel: () => Navigator.of(dialogContext).pop(),
            onSubmit: (name) async {
              final saved = group == null
                  ? await _groups.create(name)
                  : await _groups.rename(group.id, name);
              if (saved && dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
          );
        },
      ),
    );
  }

  /// Opens the rename dialog for the group with [id].
  void _renameGroup(int id) {
    final group = _groups.group(id);
    if (group != null) _openGroupNameDialog(group);
  }

  /// Asks before deleting the group with [id], then deletes it.
  Future<void> _confirmDeleteGroup(int id) async {
    final group = _groups.group(id);
    if (group == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => ConfirmDeleteDialog(
        title: 'Delete ${group.name}?',
        body:
            'Whatever was shared with ${group.name} stops being shared with '
            'its members. Their accounts and their own files stay.',
        keyPrefix: 'delete_group',
        onConfirm: () => Navigator.of(dialogContext).pop(true),
        onCancel: () => Navigator.of(dialogContext).pop(false),
      ),
    );
    if (confirmed != true || !mounted) return;
    await _report(_groups.delete(id), 'delete the group');
  }

  /// Opens the members of the group with [id] in a sheet that rebuilds with
  /// both controllers, so a member added or removed shows once the groups
  /// reload. A refusal shows in the sheet, where a snack bar would be hidden
  /// under it.
  Future<void> _openMembers(int id) async {
    final message = ValueNotifier<String?>(null);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => ListenableBuilder(
        listenable: Listenable.merge([_controllers, message]),
        builder: (sheetContext, _) {
          final group = _groups.group(id);
          // Deleted while the sheet was open, here or on another client.
          if (group == null) return const SizedBox.shrink();

          Future<void> change(Future<Object?> request, String action) async {
            final error = await request;
            if (!sheetContext.mounted) return;
            message.value = error == null
                ? null
                : Errors.message(error, action);
          }

          return GroupMembersSheet(
            group: group,
            candidates: _controller.activeAccounts,
            busyIds: _groups.busyMemberIds,
            error: message.value,
            onAdd: (userId) =>
                change(_groups.addMember(id, userId), 'add the member'),
            onRemove: (userId) =>
                change(_groups.removeMember(id, userId), 'remove the member'),
          );
        },
      ),
    );
    message.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controllers,
      builder: (context, _) {
        final c = _controller;
        final loadError = c.error;
        final isLoading = !c.hasLoaded && loadError == null;
        // A failed refresh keeps the last good rows on screen.
        final shownError = c.hasLoaded || loadError == null
            ? null
            : Errors.message(loadError, 'load the accounts');
        final accessRequestsEnabled = c.accessRequestsEnabled;
        final g = _groups;
        final groupsLoadError = g.error;
        final groupsShownError = g.hasLoaded || groupsLoadError == null
            ? null
            : Errors.message(groupsLoadError, 'load groups');
        return QuarkPageScaffold(
          title: 'Users',
          icon: QuarkIcons.person_outline,
          onRefresh: manualRefresh,
          isRefreshing: isRefreshing,
          actions: const [AppThemeToggle()],
          drawer: const AppDrawer(activeSection: QuarkDrawerSection.users),
          body: QuarkTabView(
            tabs: [
              QuarkTab(
                label: 'Accounts',
                child: ListView(
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
                        onDeny: (username) => _report(
                          c.deny(username),
                          "deny $username's request",
                        ),
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
                      actions: [
                        FilledButton.icon(
                          key: const ValueKey('users_add'),
                          onPressed: _openCreateDialog,
                          icon: const Icon(QuarkIcons.add),
                          label: const Text('Add user'),
                        ),
                      ],
                      child: UserList(
                        users: c.accounts,
                        selfUsername: c.selfUsername,
                        isLoading: isLoading,
                        error: shownError,
                        busyUsernames: c.busyUsernames,
                        onPromote: (username) => _report(
                          c.promote(username),
                          'make $username an admin',
                        ),
                        onDemote: (username) => _report(
                          c.demote(username),
                          'remove $username as an admin',
                        ),
                        onDisable: (username) =>
                            _report(c.disable(username), 'turn off $username'),
                        onEnable: (username) =>
                            _report(c.enable(username), 'turn on $username'),
                        onDelete: _confirmDelete,
                      ),
                    ),
                  ],
                ),
              ),
              QuarkTab(
                label: 'Groups',
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    GroupList(
                      groups: g.groups,
                      isLoading: !g.hasLoaded && groupsLoadError == null,
                      error: groupsShownError,
                      busyIds: g.busyGroupIds,
                      onCreate: () => _openGroupNameDialog(),
                      onMembers: _openMembers,
                      onRename: _renameGroup,
                      onDelete: _confirmDeleteGroup,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
