import 'package:flutter/material.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/utils/quark_widget.dart';
import 'package:quark/widgets/host_dialog.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The list of configured Quarks, with switch / add / edit / remove.
///
/// Shared by Settings and the login page so a user pointed at a Quark they
/// can't reach can still change hosts without getting past the auth gate
/// (#1639).
///
/// Mount this inline, never inside a dialog or a sheet. Saving a host changes
/// the active host, which re-runs the router's terms gate and can replace the
/// page underneath it (#1623); a route sitting above that page would be torn
/// down mid-transition.
class HostManager extends StatefulWidget {
  const HostManager({super.key, this.onChanged});

  /// Fired after a host is added, edited, removed, or made active, so the
  /// hosting page can reload anything derived from the active host.
  final VoidCallback? onChanged;

  @override
  State<HostManager> createState() => _HostManagerState();
}

class _HostManagerState extends State<HostManager> {
  @override
  void initState() {
    super.initState();
    AppSettings.instance.activeHostNotifier.addListener(_onActiveHostChanged);
  }

  @override
  void dispose() {
    AppSettings.instance.activeHostNotifier.removeListener(
      _onActiveHostChanged,
    );
    super.dispose();
  }

  /// Picks up host changes made elsewhere (Settings and the login page can
  /// both be alive across a navigation).
  void _onActiveHostChanged() {
    if (mounted) setState(() {});
  }

  /// Rebuilds and tells the host page, but only while still mounted — a
  /// mutation can have replaced the page via the terms gate.
  void _published() {
    if (!mounted) return;
    setState(() {});
    widget.onChanged?.call();
  }

  Future<void> _setActive(int index) async {
    await AppSettings.instance.setActiveIndex(index);
    _published();
  }

  Future<void> _addOrEdit({int? index}) async {
    final isEdit = index != null;
    final initial = isEdit ? AppSettings.instance.hosts[index] : null;

    final entry = await QuarkWidget.showDialog<HostEntry>(
      context,
      builder: (context) => HostDialog(isEdit: isEdit, initial: initial),
    );
    if (entry == null) return;

    // Saved only once the dialog is gone. Adding a host, or pointing one at a
    // new address, changes the active host — that re-runs the router's terms
    // gate and can replace this page (#1623). Doing it from inside the
    // dialog's own button tore the settings subtree down while the dialog was
    // still on screen, which is what produced the disposed-controller and
    // inherited-element errors.
    if (isEdit) {
      await AppSettings.instance.updateHost(index, entry);
    } else {
      await AppSettings.instance.addHost(entry);
    }

    _published();
  }

  /// The actions on the Quark at [index], for its menu.
  List<QuarkMenuEntry> _hostMenu(int index) => [
    QuarkMenuEntry(
      key: ValueKey('host_action_edit_$index'),
      label: 'Edit',
      onSelected: () => _addOrEdit(index: index),
    ),
    QuarkMenuEntry(
      key: ValueKey('host_action_remove_$index'),
      label: 'Remove',
      destructive: true,
      onSelected: () => _remove(index),
    ),
  ];

  Future<void> _remove(int index) async {
    final confirm = await QuarkWidget.showDialog<bool>(
      context,
      builder: (context) => QuarkWidget.alertDialog(
        title: const Text('Remove host'),
        content: const Text('Are you sure you want to remove this host?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    await AppSettings.instance.removeHost(index);
    _published();
  }

  @override
  Widget build(BuildContext context) {
    final hosts = AppSettings.instance.hosts;
    final active = AppSettings.instance.activeIndex;

    return Column(
      mainAxisSize: MainAxisSize.min,
      // Matches the full-width sizing the Settings ListView used to give these
      // children directly.
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RadioGroup<int>(
          groupValue: active,
          onChanged: (v) {
            if (v == null) return;
            _setActive(v);
          },
          child: Column(
            children: hosts.asMap().entries.map((e) {
              final idx = e.key;
              final host = e.value;
              // A right-click on the row opens the same menu as its button
              // (#2276).
              return GestureDetector(
                key: ValueKey('host_row_$idx'),
                onSecondaryTapUp: (details) => showQuarkMenu(
                  context,
                  position: details.globalPosition,
                  entries: _hostMenu(idx),
                ),
                child: Card(
                  child: ListTile(
                    leading: Radio<int>(value: idx),
                    title: Text(host.name),
                    subtitle: Text(host.hostAddress),
                    trailing: QuarkMenuButton(
                      key: ValueKey('host_menu_$idx'),
                      tooltip: 'Actions for ${host.name}',
                      entries: _hostMenu(idx),
                    ),
                    onTap: () => _setActive(idx),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        // Filled, so it takes the theme's primary colors: an ElevatedButton has
        // no theme here and fell back to Material's pale default, easy to miss
        // beside the host rows (#2072). 48dp is the minimum touch target.
        FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(kMinInteractiveDimension),
          ),
          onPressed: () => _addOrEdit(),
          icon: const Icon(QuarkIcons.add),
          label: const Text('Add Quark'),
        ),
      ],
    );
  }
}
