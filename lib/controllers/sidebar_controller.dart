import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One wide-layout sidebar's width and collapsed flag, persisted per device
/// in `SharedPreferences` so a resized or hidden sidebar stays that way across
/// reloads (#4294).
///
/// A page owns one per sidebar, named by [id] (`chat_channels`,
/// `photos_library`, ...), hands [width] and [isCollapsed] to a
/// `QuarkResizablePane` or a layout built on it, and wires [setWidth] and
/// [setCollapsed] to its callbacks. The values are stored under
/// `sidebar_<id>_width` and `sidebar_<id>_collapsed`, and are not synced
/// through the Quark.
///
/// It starts at [defaultWidth], open, and moves to the stored values once
/// they load; [loaded] completes then.
class SidebarController extends ChangeNotifier {
  /// Loads the sidebar named [id], falling back to [defaultWidth], open.
  SidebarController(this.id, {required this.defaultWidth})
    : _width = defaultWidth {
    loaded = _load();
  }

  /// The sidebar's name in the preference keys.
  final String id;

  /// The width before anything is stored.
  final double defaultWidth;

  /// Completes once the stored values are read.
  late final Future<void> loaded;

  SharedPreferences? _prefs;
  double _width;
  bool _collapsed = false;
  bool _disposed = false;

  String get _widthKey => 'sidebar_${id}_width';
  String get _collapsedKey => 'sidebar_${id}_collapsed';

  /// The sidebar's open width.
  double get width => _width;

  /// Whether the sidebar is hidden.
  bool get isCollapsed => _collapsed;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    _width = prefs.getDouble(_widthKey) ?? defaultWidth;
    _collapsed = prefs.getBool(_collapsedKey) ?? false;
    // The page may have closed before the preferences loaded.
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Sets and stores the open width.
  void setWidth(double width) {
    _width = width;
    notifyListeners();
    _prefs?.setDouble(_widthKey, width);
  }

  /// Hides or shows the sidebar, and stores it.
  void setCollapsed(bool collapsed) {
    _collapsed = collapsed;
    notifyListeners();
    _prefs?.setBool(_collapsedKey, collapsed);
  }
}
