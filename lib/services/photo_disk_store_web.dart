import 'package:quark/services/photo_disk_store.dart';

/// Web: no store. The browser's own HTTP cache keeps what it fetched.
Future<PhotoDiskStore?> openPhotoDiskStorePlatform(
  String storeKey, {
  required int Function() budgetBytes,
}) async => null;
