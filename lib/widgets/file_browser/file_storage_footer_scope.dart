import 'package:quark/services/health_service.dart';
import 'package:quark/services/storage_service.dart';

/// What the storage footer measures, and what it calls it.
///
/// The footer reports the drives the Files view is showing: the devices
/// checked under Filter devices, summed, in the unified and the per-device
/// view alike. One drive is named; more than one reads "All drives". Before
/// this, the footer always showed the root disk's health reading, so a Quark
/// whose default storage was a 1.8 TB USB drive reported only its 28 GB
/// onboard disk (#2895).
class FileStorageFooterScope {
  const FileStorageFooterScope({
    required this.label,
    required this.explanation,
    this.usedBytes,
    this.totalBytes,
  });

  /// Sums the [devices] whose `devicePath` is in [activeDevicePaths], the
  /// same per-device figures System → Storage lists.
  ///
  /// A drive that is not mounted holds no files the view could show, so it is
  /// left out. With no drive left — the device list has not loaded, or could
  /// not be — it falls back to [health], the root disk's reading.
  factory FileStorageFooterScope.of({
    required List<StorageDevice> devices,
    required Set<String> activeDevicePaths,
    HealthStatus? health,
  }) {
    final shown = devices
        .where(
          (d) =>
              activeDevicePaths.contains(d.devicePath) &&
              !d.isUnmounted &&
              d.totalBytes > 0,
        )
        .toList();
    if (shown.isEmpty) {
      return FileStorageFooterScope(
        label: kStorageFooterScope,
        explanation: kStorageFooterExplanation,
        usedBytes: health?.diskUsedBytes,
        totalBytes: health?.diskTotalBytes,
      );
    }
    final only = shown.length == 1 ? shown.single : null;
    return FileStorageFooterScope(
      label: only == null
          ? kStorageFooterAllDrives
          : only.isInternal || only.name.isEmpty
          ? kStorageFooterScope
          : only.name,
      explanation: only == null
          ? kStorageFooterAllDrivesExplanation
          : only.isInternal
          ? kStorageFooterExplanation
          : kStorageFooterDriveExplanation,
      usedBytes: shown.fold<int>(0, (sum, d) => sum + d.usedBytes),
      totalBytes: shown.fold<int>(0, (sum, d) => sum + d.totalBytes),
    );
  }

  /// The scope's name, shown before the figures.
  final String label;

  /// The longer form, for the tooltip.
  final String explanation;

  /// Bytes in use, or null before any reading has arrived.
  final int? usedBytes;

  /// Capacity in bytes, or null before any reading has arrived.
  final int? totalBytes;

  /// The used share of the capacity, from 0 to 1; 0 without a reading.
  double get usedFraction {
    final used = usedBytes;
    final total = totalBytes;
    if (used == null || total == null || total <= 0) return 0;
    return (used / total).clamp(0.0, 1.0);
  }
}

/// What the whole-disk figure means when it is the built-in disk alone.
///
/// The number is the Quark's disk, system and all, so a brand-new Quark with
/// no files in it still shows tens of gigabytes used. Beside "No files yet"
/// that reads as "Quark has already eaten my disk" rather than "this is the
/// whole device" (#2024), so the footer says which it is.
const String kStorageFooterScope = 'Device storage';

/// The tooltip for [kStorageFooterScope].
const String kStorageFooterExplanation =
    'The whole disk inside your Quark, including its system software — not '
    'just the files you have put here.';

/// The label when the view shows more than one drive.
const String kStorageFooterAllDrives = 'All drives';

/// The tooltip for [kStorageFooterAllDrives].
const String kStorageFooterAllDrivesExplanation =
    'Every drive shown here, added together — including the system software '
    'on the disk inside your Quark, not just the files you have put here.';

/// The tooltip when the view shows one plugged-in drive, labeled by its name.
const String kStorageFooterDriveExplanation =
    'The whole drive, including anything already on it — not just the files '
    'you have put here.';
