import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/sidebar_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One sidebar's width and collapsed flag, kept per device so a resized or
/// hidden sidebar stays that way across reloads (#4294).
void main() {
  test('starts at the default width, open, with nothing stored', () async {
    SharedPreferences.setMockInitialValues({});
    final sidebar = SidebarController('chat_channels', defaultWidth: 280);
    await sidebar.loaded;

    expect(sidebar.width, 280);
    expect(sidebar.isCollapsed, isFalse);
  });

  test('restores what was stored under its own keys', () async {
    SharedPreferences.setMockInitialValues({
      'sidebar_chat_channels_width': 320.0,
      'sidebar_chat_channels_collapsed': true,
      'sidebar_chat_members_width': 200.0,
    });
    final sidebar = SidebarController('chat_channels', defaultWidth: 280);
    await sidebar.loaded;

    expect(sidebar.width, 320);
    expect(sidebar.isCollapsed, isTrue);
  });

  test('stores and announces each change', () async {
    SharedPreferences.setMockInitialValues({});
    final sidebar = SidebarController('photos_library', defaultWidth: 280);
    await sidebar.loaded;
    var notified = 0;
    sidebar.addListener(() => notified++);

    sidebar.setWidth(360);
    sidebar.setCollapsed(true);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble('sidebar_photos_library_width'), 360);
    expect(prefs.getBool('sidebar_photos_library_collapsed'), isTrue);
    expect(notified, 2);
  });
}
