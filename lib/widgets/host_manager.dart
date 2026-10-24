import 'package:flutter/material.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/local_trust.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_browser_dialog_utils.dart';
import 'package:quark/utils/quark_widget.dart';
import 'package:quark/widgets/host_dialog.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The list of configured Quarks, with switch / add / edit / remove, and
/// Forget certificate for one whose certificate is pinned (#2721).
///
/// A Quark that presented a certificate other than its pin says so under its
/// address, since the app refuses to connect to it until the pin is
/// forgotten. Forget asks first, and the certificate the Quark presents next
/// is pinned only once the user has compared its fingerprint, beside the old
/// one, and trusted it (#3182).
///
/// Keys: `host_row_<index>`, `host_menu_<index>`, `host_action_edit_<index>`,
/// `host_action_remove_<index>`, `host_action_forget_certificate_<index>`,
/// `host_action_review_certificate_<index>`,
/// `host_certificate_changed_<index>` (the mismatch notice),
/// `host_certificate_unconfirmed_<index>` (the waiting-certificate notice),
/// and the dialog buttons `forget_certificate_cancel`,
/// `forget_certificate_confirm`, `review_certificate_cancel` and
/// `review_certificate_trust`.
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
    AppSettings.instance.certificatesChanged.addListener(_onActiveHostChanged);
  }

  @override
  void dispose() {
    AppSettings.instance.activeHostNotifier.removeListener(
      _onActiveHostChanged,
    );
    AppSettings.instance.certificatesChanged.removeListener(
      _onActiveHostChanged,
    );
    super.dispose();
  }

  /// Picks up host changes made elsewhere (Settings and the login page can
  /// both be alive across a navigation), and a certificate pinned, refused or
  /// forgotten.
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
    // Only a Quark with a pin, or one refused for not matching it, has
    // anything to forget.
    if (_hasCertificate(index))
      QuarkMenuEntry(
        key: ValueKey('host_action_forget_certificate_$index'),
        label: 'Forget certificate',
        onSelected: () => _forgetCertificate(index),
      ),
    if (AppSettings.instance.pendingCertificateFor(_address(index)) != null)
      QuarkMenuEntry(
        key: ValueKey('host_action_review_certificate_$index'),
        label: 'Review certificate',
        onSelected: () => _reviewCertificate(index),
      ),
    QuarkMenuEntry(
      key: ValueKey('host_action_remove_$index'),
      label: 'Remove',
      destructive: true,
      onSelected: () => _remove(index),
    ),
  ];

  String _address(int index) => AppSettings.instance.hosts[index].hostAddress;

  bool _hasCertificate(int index) {
    final address = _address(index);
    return AppSettings.instance.hasCertificateFor(address) ||
        AppSettings.instance.certificateChangedFor(address);
  }

  Future<void> _forgetCertificate(int index) async {
    final confirm = await confirmAction(
      context,
      title: 'Forget certificate',
      message:
          'Only do this if you reset or reinstalled your Quark. The app will '
          'show you the next certificate it presents, so you can check it '
          'before the app trusts it.',
      confirmLabel: 'Forget',
      keyPrefix: 'forget_certificate',
    );
    if (confirm != true) return;
    await AppSettings.instance.forgetCertificate(_address(index));
  }

  /// Shows the certificate the forgotten Quark at [index] presented, beside
  /// the one it used to be pinned to, and pins it only if the user trusts it.
  Future<void> _reviewCertificate(int index) async {
    final address = _address(index);
    final presented = AppSettings.instance.pendingCertificateFor(address);
    if (presented == null) return;
    final previous = AppSettings.instance.forgottenCertificateFor(address);
    final confirm = await QuarkWidget.showDialog<bool>(
      context,
      builder: (context) => QuarkWidget.alertDialog(
        title: const Text('Review certificate'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Trust this certificate only if its fingerprint matches the "
                "one your Quark shows. If it doesn't, you may be on a network "
                'that is impersonating your Quark.',
              ),
              const SizedBox(height: 12),
              const Text('New fingerprint (SHA-256)'),
              SelectableText(formatCertificateFingerprint(presented)),
              if (previous != null) ...[
                const SizedBox(height: 12),
                const Text('Previous fingerprint'),
                SelectableText(formatCertificateFingerprint(previous)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('review_certificate_cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const ValueKey('review_certificate_trust'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Trust'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await AppSettings.instance.confirmCertificate(address);
  }

  Future<void> _remove(int index) async {
    final confirm = await confirmAction(
      context,
      title: 'Remove host',
      message: 'Are you sure you want to remove this host?',
      confirmLabel: 'Remove',
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
              final (
                notice,
                noticeKey,
              ) = AppSettings.instance.certificateChangedFor(host.hostAddress)
                  ? (Errors.certificateChanged, 'host_certificate_changed_$idx')
                  : AppSettings.instance.pendingCertificateFor(
                          host.hostAddress,
                        ) !=
                        null
                  ? (
                      Errors.certificateUnconfirmed,
                      'host_certificate_unconfirmed_$idx',
                    )
                  : (null, null);
              // A right-click on the row opens the same menu as its button
              // (#2276).
              return GestureDetector(
                key: ValueKey('host_row_$idx'),
                // A pointer shortcut for the menu button, which is what a
                // screen reader gets; left in, it reads as an unnamed tap.
                excludeFromSemantics: true,
                onSecondaryTapUp: (details) => showQuarkMenu(
                  context,
                  position: details.globalPosition,
                  entries: _hostMenu(idx),
                ),
                child: Card(
                  // The row is the radio to a screen reader, named by the
                  // Quark it picks; the drawn radio would be a second,
                  // unnamed target for the same tap (#2603).
                  child: Semantics(
                    checked: idx == active,
                    inMutuallyExclusiveGroup: true,
                    child: ListTile(
                      leading: ExcludeSemantics(child: Radio<int>(value: idx)),
                      title: Text(host.name),
                      subtitle: notice != null
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(host.hostAddress),
                                Text(
                                  notice,
                                  key: ValueKey(noticeKey!),
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ],
                            )
                          : Text(host.hostAddress),
                      trailing: QuarkMenuButton(
                        key: ValueKey('host_menu_$idx'),
                        tooltip: 'Actions for ${host.name}',
                        entries: _hostMenu(idx),
                      ),
                      onTap: () => _setActive(idx),
                    ),
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
