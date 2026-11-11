import 'package:flutter/material.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Body of the upload-target sheet opened by `showDeviceUploadPicker`: holds
/// the choice the package's [UploadTargetPicker] asks its caller to hold.
///
/// Pops with the selected [UploadTarget], or with `null` on cancel.
class DeviceUploadPicker extends StatefulWidget {
  /// Creates the picker over [targets], starting on [initial].
  const DeviceUploadPicker({
    required this.targets,
    this.initial,
    this.notice,
    super.key,
  });

  /// The devices to choose between. Must not be empty.
  final List<UploadTarget> targets;

  /// The device chosen when the sheet opens; null starts on the first.
  final UploadTarget? initial;

  /// A line above the list, such as why the sheet opened; null shows none.
  final String? notice;

  @override
  State<DeviceUploadPicker> createState() => _DeviceUploadPickerState();
}

class _DeviceUploadPickerState extends State<DeviceUploadPicker> {
  late UploadTarget _selected = widget.initial ?? widget.targets.first;

  @override
  Widget build(BuildContext context) {
    return UploadTargetPicker(
      targets: widget.targets,
      notice: widget.notice,
      selected: _selected,
      onSelected: (target) => setState(() => _selected = target),
      onCancel: () => Navigator.pop(context),
      onConfirm: () => Navigator.pop(context, _selected),
    );
  }
}
