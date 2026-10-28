import 'package:flutter/material.dart';
import 'package:quark/controllers/model_viewer_controller.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/connection_error.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_kind.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The 3D model viewer's surface: the disconnected state when the Quark
/// cannot be reached, otherwise a [QuarkModelViewer] fed from [controller],
/// with its error sentence written by [Errors], the file's format and size
/// as its status line, and the unit and print bed the controller keeps.
class ModelViewerBody extends StatelessWidget {
  /// The viewer's state; the caller rebuilds this widget when it changes.
  final ModelViewerController controller;

  const ModelViewerBody({required this.controller, super.key});

  @override
  Widget build(BuildContext context) {
    final error = controller.error;
    if (error != null && isQuarkUnreachableError(error)) {
      return QuarkDisconnectedView(
        hostAddress: AppSettings.instance.activeHost,
        onRetry: controller.load,
      );
    }
    final size = controller.fileSize;
    final format = fileExtension(controller.path).replaceFirst('.', '');
    return QuarkModelViewer(
      mesh: controller.mesh,
      isLoading: controller.isLoading,
      error: error == null ? null : Errors.message(error, 'load the model'),
      onRetry: controller.load,
      wireframe: controller.wireframe,
      onWireframeChanged: controller.setWireframe,
      unit: controller.unit,
      onUnitChanged: controller.setUnit,
      printBed: controller.printBed,
      onPrintBedChanged: controller.setPrintBed,
      statusLabel: size == null
          ? format.toUpperCase()
          : '${format.toUpperCase()} · ${StorageDevice.formatBytes(size)}',
    );
  }
}
