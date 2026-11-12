import 'package:material_ui/material_ui.dart';
import 'package:quark/controllers/quark_discovery_controller.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/quark_discovery.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The Quarks found on the local network, for the forms that take a Quark's
/// address (#2312). Tapping one hands its entry to [onSelect].
///
/// Browses while mounted and stops when disposed. Renders nothing where the
/// platform cannot browse — the web, macOS and Windows — so typing the address is
/// the only way in there.
class NearbyQuarks extends StatefulWidget {
  const NearbyQuarks({super.key, required this.onSelect, this.browse})
    : _useDefault = true;

  /// Lists nothing, as on a platform that cannot browse, whatever this
  /// platform's [quarkBrowser] is. Lets a test cover that case on Linux, which
  /// browses (#3152).
  const NearbyQuarks.withoutBrowser({super.key, required this.onSelect})
    : browse = null,
      _useDefault = false;

  /// Called with the Quark whose row was tapped.
  final ValueChanged<HostEntry> onSelect;

  /// The browser to use. Defaults to [quarkBrowser]; a test passes a fake.
  final QuarkBrowser? browse;

  /// Whether a null [browse] falls back to [quarkBrowser].
  final bool _useDefault;

  @override
  State<NearbyQuarks> createState() => _NearbyQuarksState();
}

class _NearbyQuarksState extends State<NearbyQuarks> {
  late final QuarkDiscoveryController? _controller = switch (widget.browse ??
      (widget._useDefault ? quarkBrowser : null)) {
    final browse? => QuarkDiscoveryController(browse: browse),
    null => null,
  };

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final error = controller.error;
        return DiscoveredQuarkList(
          quarks: [
            for (final q in controller.quarks)
              HostItem(name: q.name, address: q.hostAddress),
          ],
          isLoading: controller.isSearching,
          error: error == null
              ? null
              : Errors.message(error, 'look for Quarks on this network'),
          onSelect: (item) => widget.onSelect(
            HostEntry(name: item.name, hostAddress: item.address),
          ),
        );
      },
    );
  }
}
