import 'package:quark/services/app_settings.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/quark_widget_items.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The storage devices as they are now, past [StorageService]'s cache: a
/// drive plugged in or enabled a moment ago has to be offered (#3191).
Future<List<StorageDevice>> listDevicesFresh() {
  StorageService.invalidateDeviceCache();
  return StorageService.listDevices();
}

/// What the device picker says when no enabled device holds the Default
/// Storage role. A default drive that is unplugged is not listed at all, so
/// it reads the same as no default (#3194).
const noDefaultDeviceNotice = 'No default storage device is connected.';

/// What the device picker says when the default storage device is listed
/// but not enabled (#3194).
const defaultDeviceDisabledNotice =
    'The default storage device is not enabled.';

/// The serial of the device an upload or a new folder goes to — `''` for
/// built-in storage — or null when the user dismissed the picker.
///
/// Only enabled devices are destinations. [viewedSerial] is the one device
/// the view is filtered to, null when it shows several: that device is the
/// destination without asking. Otherwise a device listed alone is the
/// destination, and so is the default storage device an admin set (#3194),
/// unless [chooseDevice] asks for the picker. [pick] chooses between
/// several, starting on `initial`: the default storage device, else the
/// device chosen last time, else the first, each only when it can be
/// chosen. What [pick] answers is kept in [AppSettings] for next time
/// (#3192).
///
/// With no enabled default storage device, [pick] is handed a `notice`
/// saying so: [defaultDeviceDisabledNotice] when the default is listed but
/// not enabled, else [noDefaultDeviceNotice]. Otherwise the notice is null.
///
/// A drive that is connected but not enabled is passed to [pick] as an
/// unavailable target, so the user sees it and what enables it: one beside
/// a single enabled device is enough to ask. [listDevices] answers only
/// with devices the Quark detects, so a drive that is not connected is not
/// listed at all.
///
/// Throws what [listDevices] threw. A destination that cannot be worked out
/// is not built-in storage; the caller stops and says so (#3191).
Future<String?> resolveUploadSerial({
  required Future<UploadTarget?> Function(
    List<UploadTarget> targets,
    UploadTarget initial,
    String? notice,
  )
  pick,
  String? viewedSerial,
  bool chooseDevice = false,
  Future<List<StorageDevice>> Function() listDevices = listDevicesFresh,
}) async {
  final targets = [
    for (final device in await listDevices()) device.toUploadTarget(),
  ];
  final enabled = [
    for (final target in targets)
      if (target.unavailableReason == null) target,
  ];
  if (enabled.any((target) => target.serial == viewedSerial)) {
    return viewedSerial;
  }
  if (enabled.isEmpty || targets.length == 1) {
    return enabled.firstOrNull?.serial ?? '';
  }
  final byDefault = enabled.where((target) => target.isDefault).firstOrNull;
  if (byDefault != null && !chooseDevice) return byDefault.serial;

  final settings = AppSettings.instance;
  final picked = await pick(
    targets,
    byDefault ??
        enabled.firstWhere(
          (target) => target.serial == settings.lastUploadSerial,
          orElse: () => enabled.first,
        ),
    byDefault != null
        ? null
        : targets.any((target) => target.isDefault)
        ? defaultDeviceDisabledNotice
        : noDefaultDeviceNotice,
  );
  if (picked != null) await settings.setLastUploadSerial(picked.serial);
  return picked?.serial;
}
