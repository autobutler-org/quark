import 'package:flutter/material.dart';
import 'package:quark/widgets/device_upload_picker/device_upload_picker.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Shows a bottom sheet letting the user pick a target device for upload.
///
/// Returns the selected [UploadTarget], or `null` if the user cancels.
Future<UploadTarget?> showDeviceUploadPicker(
  BuildContext context,
  List<UploadTarget> targets,
) {
  return showModalBottomSheet<UploadTarget>(
    context: context,
    builder: (ctx) => DeviceUploadPicker(targets: targets),
  );
}
