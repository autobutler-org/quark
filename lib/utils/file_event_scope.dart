import 'package:quark/services/events_service.dart';
import 'package:quark/utils/file_browser_path_utils.dart';

/// Whether [event] can change the listing of [folderPath], the folder the
/// Files page has open (#2763).
///
/// Only events that change listings at all ([FileEvent.changesListing]) count.
/// Of those, one counts when its path or its move target is:
///
/// - the open folder, or anything under it: an upload names the folder it
///   went into and creates that folder's parents on the way, so a change at
///   any depth can add a child here;
/// - an ancestor of the open folder: deleting or moving one takes this folder
///   with it, and access set on one is inherited here.
///
/// An event with no path, a resync or an access change after a group edit,
/// cannot be placed, so it counts. The device serial is not compared: a
/// same-named folder on another drive costs a refresh, never a stale listing.
bool eventAffectsFolder(FileEvent event, String folderPath) {
  if (!event.changesListing) return false;
  if (normalizePath(event.path).isEmpty) return true;
  final folder = normalizePath(folderPath);
  return [event.path, ?event.newPath].any((p) {
    final path = normalizePath(p);
    return _isWithin(path, folder) || _isWithin(folder, path);
  });
}

/// Whether [path] is [root] or under it. Both are normalized; the empty root
/// holds everything.
bool _isWithin(String path, String root) =>
    root.isEmpty || path == root || path.startsWith('$root/');
