import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import 'widgets/album_sidebar_demo.dart';
import 'widgets/album_tree_demo.dart';
import 'widgets/framed_viewport.dart';
import 'widgets/password_strength_demo.dart';
import 'widgets/split_view_demo.dart';
import 'widgets/token_swatches.dart';

/// One widget in the gallery: a live example built from fake data.
///
/// The builder is handed a `log` callback. Wire every callback the widget
/// exposes to it, so the gallery's event panel shows what the widget emits and
/// a callback that never fires is visible.
class GalleryEntry {
  /// Creates an entry for [name], filed under [group], rendering [build].
  const GalleryEntry({
    required this.name,
    required this.group,
    required this.build,
  });

  /// The class name of the widget, matching its entry in `docs.g.dart`.
  final String name;

  /// The heading this entry is listed under, usually its `lib/src/` directory.
  final String group;

  /// Builds the example. Pass `log` to every callback the widget takes.
  final Widget Function(BuildContext context, void Function(String event) log)
  build;
}

/// Every widget the gallery can show.
///
/// A package test fails when a widget exported from `quark_widgets.dart` has no
/// entry here, so this list stays complete as widgets land.
final List<GalleryEntry> registry = [
  GalleryEntry(
    name: 'Theme tokens',
    group: 'Theme',
    build: (context, log) => const TokenSwatches(),
  ),

  // ── Core ──────────────────────────────────────────────────────────────────
  GalleryEntry(
    name: 'EmptyStateWidget',
    group: 'Core',
    build: (context, log) => EmptyStateWidget(
      icon: QuarkIcons.folder_outlined,
      headline: 'This folder is empty',
      subtext: 'Upload a file to get started.',
      action: FilledButton(
        onPressed: () => log('EmptyStateWidget action tapped'),
        child: const Text('Upload'),
      ),
    ),
  ),
  GalleryEntry(
    name: 'QuarkFileIcon',
    group: 'Core',
    build: (context, log) => Wrap(
      spacing: 24,
      runSpacing: 16,
      children: [
        for (final entry in const [
          ('Photos', true),
          ('holiday.jpg', false),
          ('clip.mp4', false),
          ('song.flac', false),
          ('report.pdf', false),
          ('notes.qdoc', false),
          ('budget.qsheet', false),
          ('backup.zip', false),
          ('unknown.xyz', false),
        ])
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              QuarkFileIcon(name: entry.$1, isDir: entry.$2, size: 32),
              const SizedBox(height: 4),
              Text(entry.$1, style: const TextStyle(fontSize: 11)),
            ],
          ),
      ],
    ),
  ),
  GalleryEntry(
    name: 'QuarkLoader',
    group: 'Core',
    build: (context, log) => Wrap(
      spacing: 32,
      runSpacing: 24,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final size in const [24.0, 36.0, 64.0]) QuarkLoader(size: size),
        // The reduced-motion fallback: rings hold their tilt, opacity pulses.
        MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: const QuarkLoader(size: 64),
        ),
      ],
    ),
  ),
  GalleryEntry(
    name: 'QuarkStorageBar',
    group: 'Core',
    build: (context, log) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final fraction in const [0.2, 0.8, 0.95]) ...[
          Text('${(fraction * 100).round()}% used'),
          const SizedBox(height: 4),
          QuarkStorageBar(usedFraction: fraction),
          const SizedBox(height: 16),
        ],
      ],
    ),
  ),
  GalleryEntry(
    name: 'CopyButton',
    group: 'Core',
    build: (context, log) => Wrap(
      spacing: 16,
      runSpacing: 16,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        CopyButton(
          text: 'quark-token-1234',
          onCopy: (value) async => log('CopyButton.onCopy($value)'),
        ),
        CopyButton(
          text: 'quark-token-1234',
          label: 'Copy phrase',
          variant: CopyButtonVariant.outlined,
          onCopy: (value) async => log('CopyButton.onCopy($value)'),
        ),
        CopyButton(
          text: 'quark-token-1234',
          unavailableReason: 'Clipboard unavailable — use HTTPS to enable',
          onCopy: (value) async => log('never called'),
        ),
      ],
    ),
  ),
  GalleryEntry(
    name: 'PasswordStrengthBar',
    group: 'Core',
    build: (context, log) => Wrap(
      spacing: 32,
      runSpacing: 24,
      children: [
        const PasswordStrengthDemo(),
        // The reduced-motion fallback: the fill jumps instead of sliding.
        MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: const PasswordStrengthDemo(),
        ),
      ],
    ),
  ),
  GalleryEntry(
    name: 'ConfirmDeleteDialog',
    group: 'Core',
    build: (context, log) => ConfirmDeleteDialog(
      title: 'Delete bob?',
      body:
          "bob won't be able to sign in again. The files they own stay on "
          'this Quark and become yours.',
      keyPrefix: 'delete_user',
      onConfirm: () => log('ConfirmDeleteDialog.onConfirm'),
      onCancel: () => log('ConfirmDeleteDialog.onCancel'),
    ),
  ),
  GalleryEntry(
    name: 'QuarkDisconnectedView',
    group: 'Core',
    build: (context, log) => SizedBox(
      height: 520,
      child: QuarkDisconnectedView(
        hostAddress: 'https://quark.local',
        onRetry: () => log('QuarkDisconnectedView.onRetry'),
        onManageHosts: () => log('QuarkDisconnectedView.onManageHosts'),
      ),
    ),
  ),
  GalleryEntry(
    name: 'QuarkDisconnectedBanner',
    group: 'Core',
    build: (context, log) => QuarkDisconnectedBanner(
      onRetry: () => log('QuarkDisconnectedBanner.onRetry'),
    ),
  ),

  GalleryEntry(
    name: 'ScrollUpHint',
    group: 'Core',
    build: (context, log) => const SizedBox(
      height: 120,
      child: Stack(
        children: [
          Center(child: Text('Scrolled past something above')),
          Positioned(top: 0, left: 0, right: 0, child: ScrollUpHint()),
        ],
      ),
    ),
  ),

  // ── Layout ────────────────────────────────────────────────────────────────
  GalleryEntry(
    name: 'ConnectionIndicator',
    group: 'Layout',
    build: (context, log) => const Row(
      spacing: 8,
      children: [
        ConnectionIndicator(mode: ConnectionMode.local, label: 'Local'),
        ConnectionIndicator(mode: ConnectionMode.remote, label: 'Remote'),
        ConnectionIndicator(mode: ConnectionMode.offline, label: 'Offline'),
        Text('local, remote, offline'),
      ],
    ),
  ),
  GalleryEntry(
    name: 'QuarkAppBar',
    group: 'Layout',
    build: (context, log) => SizedBox(
      height: 360,
      child: Scaffold(
        appBar: QuarkAppBar(
          label: 'Photos',
          icon: QuarkIcons.photo_library_outlined,
          // Refresh is a slot, not an action: it always lands beside the
          // brand button, and a page cannot move it.
          onRefresh: () => log('QuarkAppBar.onRefresh'),
          actions: [
            ThemeToggleButton(
              mode: ThemeMode.dark,
              onChanged: (mode) => log('ThemeToggleButton.onChanged($mode)'),
            ),
          ],
        ),
        drawer: QuarkDrawer(
          activeSection: QuarkDrawerSection.photos,
          hosts: const [HostItem(name: 'Home', address: 'quark.local')],
          activeHostIndex: 0,
          onTapFiles: () => log('QuarkDrawer files'),
        ),
        body: const Center(child: Text('Tap the brand button')),
      ),
    ),
  ),
  GalleryEntry(
    name: 'QuarkAppBarTrailing',
    group: 'Layout',
    build: (context, log) => SizedBox(
      height: 200,
      child: QuarkAppBarTrailing(
        actions: [
          JobsBadge(
            runningCount: 1,
            onTap: () => log('QuarkAppBarTrailing JobsBadge.onTap'),
          ),
        ],
        child: Scaffold(
          appBar: QuarkAppBar(
            label: 'Health',
            icon: QuarkIcons.monitor_heart_outlined,
            onRefresh: () => log('QuarkAppBarTrailing page refresh'),
          ),
          body: const Center(
            child: Text('The badge comes from the scope, after the page'),
          ),
        ),
      ),
    ),
  ),
  GalleryEntry(
    name: 'QuarkAppBarBottom',
    group: 'Layout',
    build: (context, log) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final width in const [1000.0, 360.0]) ...[
          Text(
            width >= QuarkAppBarBottom.collapseBreakpoint
                ? 'wide: the actions sit in the row'
                : 'narrow: they collapse into a labeled menu',
          ),
          const SizedBox(height: 8),
          FramedViewport(
            width: width,
            height: 200,
            child: Scaffold(
              appBar: QuarkAppBar(
                label: 'Files',
                icon: QuarkIcons.folder_outlined,
                bottom: QuarkAppBarBottom(
                  lead: const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Home / Documents'),
                  ),
                  actions: [
                    QuarkBarChip(
                      icon: QuarkIcons.upload_rounded,
                      label: 'Upload',
                      onPressed: () => log('QuarkAppBarBottom action: Upload'),
                    ),
                    QuarkBarChip(
                      icon: QuarkIcons.create_new_folder_outlined,
                      label: 'New folder',
                      onPressed: () =>
                          log('QuarkAppBarBottom action: New folder'),
                    ),
                  ],
                  menuChildren: [
                    MenuItemButton(
                      onPressed: () => log('QuarkAppBarBottom menu: List'),
                      leadingIcon: const Icon(QuarkIcons.view_list_rounded),
                      child: const Text('List'),
                    ),
                    MenuItemButton(
                      onPressed: () => log('QuarkAppBarBottom menu: Grid'),
                      leadingIcon: const Icon(QuarkIcons.grid_view_rounded),
                      child: const Text('Grid'),
                    ),
                  ],
                ),
              ),
              body: const SizedBox.shrink(),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ],
    ),
  ),
  GalleryEntry(
    name: 'QuarkBarChip',
    group: 'Layout',
    build: (context, log) => Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        QuarkBarChip(
          icon: QuarkIcons.upload_rounded,
          label: 'Upload',
          onPressed: () => log('QuarkBarChip(Upload).onPressed'),
        ),
        QuarkBarChip(
          icon: QuarkIcons.folder_copy_outlined,
          label: 'Unified',
          tooltip: 'All your drives shown together',
          active: true,
          onPressed: () => log('QuarkBarChip(Unified).onPressed'),
        ),
        const QuarkBarChip(
          icon: QuarkIcons.create_new_folder_outlined,
          label: 'New folder',
          onPressed: null,
        ),
      ],
    ),
  ),
  GalleryEntry(
    name: 'QuarkBarIconButton',
    group: 'Layout',
    build: (context, log) => Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        QuarkBarIconButton(
          icon: QuarkIcons.check_circle_outline,
          tooltip: 'Select',
          onPressed: () => log('QuarkBarIconButton(Select).onPressed'),
        ),
        QuarkBarIconButton(
          icon: QuarkIcons.search_rounded,
          tooltip: 'Search',
          onPressed: () => log('QuarkBarIconButton(Search).onPressed'),
        ),
        QuarkBarIconButton(
          icon: QuarkIcons.delete_outline,
          tooltip: 'Delete',
          destructive: true,
          onPressed: () => log('QuarkBarIconButton(Delete).onPressed'),
        ),
        const QuarkBarIconButton(
          icon: QuarkIcons.save_outlined,
          tooltip: 'Saving',
          isBusy: true,
          onPressed: null,
        ),
        const QuarkBarIconButton(
          icon: QuarkIcons.arrow_upward_rounded,
          tooltip: 'Up one level',
          onPressed: null,
        ),
      ],
    ),
  ),
  GalleryEntry(
    name: 'QuarkBarSegmentedToggle',
    group: 'Layout',
    build: (context, log) => Align(
      alignment: Alignment.centerLeft,
      child: QuarkBarSegmentedToggle(
        segments: const [
          QuarkBarSegment(
            id: 'list',
            icon: QuarkIcons.view_list_rounded,
            label: 'List',
          ),
          QuarkBarSegment(
            id: 'grid',
            icon: QuarkIcons.grid_view_rounded,
            label: 'Grid',
          ),
        ],
        selectedId: 'list',
        onSelected: (id) => log('QuarkBarSegmentedToggle.onSelected($id)'),
      ),
    ),
  ),
  GalleryEntry(
    name: 'QuarkBrandButton',
    group: 'Layout',
    build: (context, log) => Align(
      alignment: Alignment.centerLeft,
      child: QuarkBrandButton(
        label: 'Files',
        onTap: () => log('QuarkBrandButton.onTap'),
      ),
    ),
  ),
  GalleryEntry(
    name: 'QuarkCheckerboard',
    group: 'Layout',
    build: (context, log) => SizedBox(
      height: 220,
      // A white glyph and a black one, so the board can be judged the way it
      // is used: transparent artwork that could be either.
      child: QuarkCheckerboard(
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final color in const [Colors.white, Colors.black])
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Icon(Icons.auto_awesome, size: 72, color: color),
                ),
            ],
          ),
        ),
      ),
    ),
  ),
  GalleryEntry(
    name: 'QuarkDrawer',
    group: 'Layout',
    build: (context, log) => SizedBox(
      height: 520,
      width: 304,
      child: QuarkDrawer(
        activeSection: QuarkDrawerSection.photos,
        hosts: const [
          HostItem(name: 'Home', address: 'quark.local'),
          HostItem(name: 'Cabin', address: 'cabin.local:8443'),
        ],
        activeHostIndex: 0,
        onSelectHost: (index) => log('QuarkDrawer.onSelectHost($index)'),
        onTapFiles: () => log('QuarkDrawer.onTapFiles'),
        onTapPhotos: () => log('QuarkDrawer.onTapPhotos'),
        onTapTrash: () => log('QuarkDrawer.onTapTrash'),
        onTapDocs: () => log('QuarkDrawer.onTapDocs'),
        onTapSheets: () => log('QuarkDrawer.onTapSheets'),
        onTapSystem: () => log('QuarkDrawer.onTapSystem'),
        onTapVault: () => log('QuarkDrawer.onTapVault'),
        onTapUsers: () => log('QuarkDrawer.onTapUsers'),
        onTapSettings: () => log('QuarkDrawer.onTapSettings'),
      ),
    ),
  ),
  GalleryEntry(
    name: 'QuarkPageScaffold',
    group: 'Layout',
    build: (context, log) => FramedViewport(
      width: 480,
      height: 420,
      child: QuarkPageScaffold(
        title: 'Photos',
        icon: QuarkIcons.photo_library_outlined,
        onRefresh: () => log('QuarkPageScaffold.onRefresh'),
        drawer: QuarkDrawer(
          activeSection: QuarkDrawerSection.photos,
          onTapFiles: () => log('QuarkDrawer.onTapFiles'),
        ),
        bottomBar: PhotoSelectionBar(
          selectedCount: 3,
          onAddToAlbum: () => log('PhotoSelectionBar.onAddToAlbum'),
        ),
        body: const Center(child: Text('The page body goes here')),
      ),
    ),
  ),
  GalleryEntry(
    name: 'QuarkSplitView',
    group: 'Layout',
    build: (context, log) => SplitViewDemo(log: log),
  ),
  GalleryEntry(
    name: 'QuarkSection',
    group: 'Layout',
    build: (context, log) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        QuarkSection(
          title: 'Backend hosts',
          actions: [
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add a host',
              onPressed: () => log('QuarkSection action: add a host'),
            ),
          ],
          child: const Card(
            child: ListTile(title: Text('https://quark.local')),
          ),
        ),
        const SizedBox(height: 24),
        const QuarkSection(
          title: 'Software Bill of Materials',
          icon: Icons.info_outline,
          child: Card(child: ListTile(title: Text('142 packages'))),
        ),
      ],
    ),
  ),
  GalleryEntry(
    name: 'QuarkToolbar',
    group: 'Layout',
    build: (context, log) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('wrap: grows taller instead of overflowing'),
        const SizedBox(height: 8),
        FramedViewport(
          width: 360,
          height: 120,
          child: QuarkToolbar(
            actions: [
              for (final label in const ['Select all', 'Download', 'Delete'])
                FilledButton(
                  onPressed: () => log('QuarkToolbar action: $label'),
                  child: Text(label),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text('scroll: stays one line tall in a fixed-height bar'),
        const SizedBox(height: 8),
        FramedViewport(
          width: 360,
          height: 72,
          child: QuarkToolbar(
            overflow: QuarkToolbarOverflow.scroll,
            actions: [
              for (final label in const ['Select all', 'Download', 'Delete'])
                FilledButton(
                  onPressed: () => log('QuarkToolbar action: $label'),
                  child: Text(label),
                ),
            ],
          ),
        ),
      ],
    ),
  ),
  GalleryEntry(
    name: 'RefreshIconButton',
    group: 'Layout',
    build: (context, log) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        RefreshIconButton(
          isRefreshing: false,
          onPressed: () => log('RefreshIconButton.onPressed'),
        ),
        const RefreshIconButton(isRefreshing: true, onPressed: null),
      ],
    ),
  ),
  GalleryEntry(
    name: 'ThemeToggleButton',
    group: 'Layout',
    build: (context, log) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final mode in ThemeMode.values)
          ThemeToggleButton(
            mode: mode,
            onChanged: (next) => log('ThemeToggleButton: $mode -> $next'),
          ),
      ],
    ),
  ),
  GalleryEntry(
    name: 'QuarkTabView',
    group: 'Layout',
    build: (context, log) => SizedBox(
      height: 320,
      child: QuarkTabView(
        tabs: [
          QuarkTab(
            label: 'Accounts',
            child: ListView(
              children: const [
                ListTile(title: Text('ada')),
                ListTile(title: Text('bob')),
              ],
            ),
          ),
          QuarkTab(
            label: 'Groups',
            child: ListView(
              children: const [
                ListTile(title: Text('everyone')),
                ListTile(title: Text('Family')),
              ],
            ),
          ),
        ],
      ),
    ),
  ),
  GalleryEntry(
    name: 'QuarkTabView (controlled)',
    group: 'Layout',
    // The caller holds the tab, the way a page whose tabs have URLs does
    // (#2349). Five tabs, so a narrow window shows the bar scrolling. Both
    // views share the selection: picking a tab in one moves the other from
    // outside, and the lower one, under reduced motion, switches without
    // sliding.
    build: (context, log) {
      var selected = 0;
      const labels = [
        'General',
        'Account',
        'Storage',
        'Notifications',
        'About',
      ];
      return StatefulBuilder(
        builder: (context, setState) {
          final view = QuarkTabView(
            selectedIndex: selected,
            onTabSelected: (index) {
              log('QuarkTabView: onTabSelected($index)');
              setState(() => selected = index);
            },
            tabs: [
              for (final label in labels)
                QuarkTab(
                  label: label,
                  child: Center(child: Text(label)),
                ),
            ],
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 200, child: view),
              const SizedBox(height: 16),
              const Text('Reduced motion'),
              SizedBox(
                height: 200,
                child: MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(disableAnimations: true),
                  child: view,
                ),
              ),
            ],
          );
        },
      );
    },
  ),

  // ── File browser ──────────────────────────────────────────────────────────
  GalleryEntry(
    name: 'FileBreadcrumbBar',
    group: 'File browser',
    build: (context, log) => FileBreadcrumbBar(
      currentPath: '/photos/2024/june',
      isSearchMode: false,
      onGoHome: () => log('FileBreadcrumbBar.onGoHome'),
      onGoUp: () => log('FileBreadcrumbBar.onGoUp'),
      onPathSelected: (path) => log('FileBreadcrumbBar.onPathSelected($path)'),
    ),
  ),
  GalleryEntry(
    name: 'FileBrowserHeader',
    group: 'File browser',
    build: (context, log) => FileBrowserHeader(
      isSearchMode: true,
      searchQuery: 'invoice',
      resultCount: 4,
      onClose: () => log('FileBrowserHeader.onClose'),
    ),
  ),
  GalleryEntry(
    name: 'FileSelectionBar',
    group: 'File browser',
    build: (context, log) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FileSelectionBar(
          selectedCount: 2,
          totalCount: 7,
          onSelectAll: () => log('FileSelectionBar.onSelectAll'),
          onDeselectAll: () => log('FileSelectionBar.onDeselectAll'),
          onCancel: () => log('FileSelectionBar.onCancel'),
          onDelete: () => log('FileSelectionBar.onDelete'),
        ),
        const SizedBox(height: 16),
        // The trash's variant: restore, and a delete that is permanent.
        FileSelectionBar(
          selectedCount: 2,
          totalCount: 7,
          onSelectAll: () => log('FileSelectionBar.onSelectAll'),
          onDeselectAll: () => log('FileSelectionBar.onDeselectAll'),
          onCancel: () => log('FileSelectionBar.onCancel'),
          onRestore: () => log('FileSelectionBar.onRestore'),
          onDelete: () => log('FileSelectionBar.onDelete'),
          deleteTooltip: 'Delete permanently',
        ),
      ],
    ),
  ),
  GalleryEntry(
    name: 'FileShortcutBar',
    group: 'File browser',
    build: (context, log) => FileShortcutBar(
      shortcuts: const [
        FileShortcut(
          id: 'my_files',
          label: 'My files',
          icon: QuarkIcons.home_rounded,
        ),
        FileShortcut(
          id: 'groups',
          label: 'Groups',
          icon: QuarkIcons.group_outlined,
        ),
        FileShortcut(
          id: 'all_files',
          label: 'All files',
          icon: QuarkIcons.folder_rounded,
        ),
      ],
      onSelected: (id) => log('FileShortcutBar.onSelected($id)'),
    ),
  ),
  GalleryEntry(
    name: 'SharedRootsSheet',
    group: 'File browser',
    build: (context, log) => SharedRootsSheet(
      items: const [
        SharedRootItem(path: 'users/alice/Trip', name: 'Trip', owner: 'alice'),
        SharedRootItem(path: 'Family', name: 'Family', owner: 'carol'),
        SharedRootItem(path: 'Loose', name: 'Loose'),
      ],
      onPicked: (path) => log('SharedRootsSheet.onPicked($path)'),
    ),
  ),
  GalleryEntry(
    name: 'NewFileDialog',
    group: 'File browser',
    build: (context, log) => NewFileDialog(
      onCreate: (name) => log('NewFileDialog.onCreate($name)'),
      onCancel: () => log('NewFileDialog.onCancel'),
    ),
  ),
  GalleryEntry(
    name: 'UploadConflictDialog',
    group: 'File browser',
    build: (context, log) => UploadConflictDialog(
      fileName: 'holiday.jpg',
      showApplyToAll: true,
      applyToAll: false,
      onApplyToAllChanged: (value) =>
          log('UploadConflictDialog.onApplyToAllChanged($value)'),
      onKeepBoth: () => log('UploadConflictDialog.onKeepBoth'),
      onReplace: () => log('UploadConflictDialog.onReplace'),
      onCancel: () => log('UploadConflictDialog.onCancel'),
    ),
  ),

  // ── Jobs ──────────────────────────────────────────────────────────────────
  GalleryEntry(
    name: 'JobsBadge',
    group: 'Jobs',
    build: (context, log) => Row(
      children: [
        JobsBadge(runningCount: 0, onTap: () => log('JobsBadge(0).onTap')),
        const Text('0 hides the badge; 2 shows it:'),
        JobsBadge(runningCount: 2, onTap: () => log('JobsBadge(2).onTap')),
      ],
    ),
  ),
  GalleryEntry(
    name: 'JobList',
    group: 'Jobs',
    build: (context, log) => SizedBox(
      height: 360,
      child: JobList(
        items: _galleryJobs,
        onCancel: (id) => log('JobList.onCancel($id)'),
        onRetry: (id) => log('JobList.onRetry($id)'),
      ),
    ),
  ),

  // ── Photos ────────────────────────────────────────────────────────────────
  GalleryEntry(
    name: 'PhotoSelectionBar',
    group: 'Photos',
    build: (context, log) => Column(
      children: [
        PhotoSelectionBar(
          selectedCount: 3,
          onAddToAlbum: () => log('PhotoSelectionBar.onAddToAlbum'),
        ),
        const SizedBox(height: 16),
        PhotoSelectionBar(
          selectedCount: 0,
          onAddToAlbum: () => log('never called'),
        ),
      ],
    ),
  ),
  GalleryEntry(
    name: 'LiveBadge',
    group: 'Photos',
    build: (context, log) => Container(
      width: 240,
      height: 120,
      color: const Color(0xFF7C8AA0),
      alignment: Alignment.topLeft,
      padding: const EdgeInsets.all(4),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          // The thumbnail chip, then the viewer badge loading and ready.
          LiveBadge(),
          LiveBadge(ready: false),
          LiveBadge(ready: true),
        ],
      ),
    ),
  ),

  GalleryEntry(
    name: 'PhotoGridTile',
    group: 'Photos',
    build: (context, log) => Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final (label, item, selectionMode, selected) in const [
          ('plain', PhotoItem(id: 'p1', name: 'beach.jpg'), false, false),
          (
            'favorite, live',
            PhotoItem(
              id: 'p2',
              name: 'wave.heic',
              isFavorite: true,
              hasLiveVideo: true,
            ),
            false,
            false,
          ),
          ('unselected', PhotoItem(id: 'p3', name: 'dune.jpg'), true, false),
          ('selected', PhotoItem(id: 'p4', name: 'pier.jpg'), true, true),
        ])
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: 120,
                child: PhotoGridTile(
                  item: item,
                  selectionMode: selectionMode,
                  isSelected: selected,
                  thumbnailBuilder: (context, photo) =>
                      const ColoredBox(color: Color(0xFF7C8AA0)),
                  onTap: () => log('PhotoGridTile.onTap(${item.id})'),
                  onLongPress: () =>
                      log('PhotoGridTile.onLongPress(${item.id})'),
                  onDoubleTap: () =>
                      log('PhotoGridTile.onDoubleTap(${item.id})'),
                  onMenu: selectionMode
                      ? null
                      : (_) => log('PhotoGridTile.onMenu(${item.id})'),
                ),
              ),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(fontSize: 11)),
            ],
          ),
      ],
    ),
  ),
  GalleryEntry(
    name: 'PhotoGrid',
    group: 'Photos',
    build: (context, log) => SizedBox(
      height: 420,
      child: CustomScrollView(
        slivers: [
          PhotoGrid(
            photos: [
              for (var i = 0; i < 14; i++)
                PhotoItem(
                  id: 'p$i',
                  name: 'photo_$i.jpg',
                  isRemote: i % 5 != 4,
                  isFavorite: i % 4 == 1,
                  hasLiveVideo: i % 6 == 2,
                ),
            ],
            crossAxisCount: 4,
            hasMore: true,
            emptyState: const Center(child: Text('No photos yet')),
            thumbnailBuilder: (context, photo) =>
                const ColoredBox(color: Color(0xFF7C8AA0)),
            onTap: (i) => log('PhotoGrid.onTap($i)'),
            onLongPress: (i) => log('PhotoGrid.onLongPress($i)'),
            onDoubleTap: (i) => log('PhotoGrid.onDoubleTap($i)'),
            onMenu: (i, position) => log('PhotoGrid.onMenu($i)'),
          ),
        ],
      ),
    ),
  ),
  GalleryEntry(
    name: 'PhotoCategoryList',
    group: 'Photos',
    build: (context, log) => SizedBox(
      width: 280,
      child: PhotoCategoryList(
        categories: _galleryCategories,
        selectedId: 'quark',
        expanded: true,
        onToggleExpanded: () => log('PhotoCategoryList.onToggleExpanded'),
        onSelected: (id) => log('PhotoCategoryList.onSelected($id)'),
      ),
    ),
  ),
  GalleryEntry(
    name: 'PhotoLibrarySidebar',
    group: 'Photos',
    build: (context, log) => SizedBox(
      width: 280,
      height: 520,
      child: PhotoLibrarySidebar(
        columns: 4,
        minColumns: 1,
        maxColumns: 8,
        onColumnsChanged: (c) =>
            log('PhotoLibrarySidebar.onColumnsChanged($c)'),
        categories: PhotoCategoryList(
          categories: _galleryCategories,
          selectedId: 'quark',
          expanded: false,
          onToggleExpanded: () => log('PhotoCategoryList.onToggleExpanded'),
          onSelected: (id) => log('PhotoCategoryList.onSelected($id)'),
        ),
        albums: AlbumSidebarDemo(
          albums: _galleryAlbumList,
          shrinkWrap: QuarkSplitView.isCollapsed(context),
          log: log,
        ),
      ),
    ),
  ),

  // ── Albums ────────────────────────────────────────────────────────────────
  GalleryEntry(
    name: 'AlbumTreeTile',
    group: 'Albums',
    build: (context, log) => AlbumTreeDemo(log: log),
  ),
  GalleryEntry(
    name: 'AlbumSidebar',
    group: 'Albums',
    build: (context, log) => SizedBox(
      width: 280,
      height: 360,
      child: AlbumSidebarDemo(albums: _galleryAlbumList, log: log),
    ),
  ),
  GalleryEntry(
    name: 'AlbumPickerSheet',
    group: 'Albums',
    build: (context, log) => SizedBox(
      height: 420,
      child: AlbumPickerSheet(
        selectedCount: 3,
        albums: _galleryAlbumList,
        onPicked: (a) => log('AlbumPickerSheet.onPicked(${a.name})'),
        onRetry: () => log('AlbumPickerSheet.onRetry'),
      ),
    ),
  ),
  GalleryEntry(
    name: 'AddToAlbumSheet',
    group: 'Albums',
    build: (context, log) => SizedBox(
      height: 420,
      child: AddToAlbumSheet(
        albums: _galleryAlbumList,
        memberAlbumIds: const {4},
        onToggle: (a) => log('AddToAlbumSheet.onToggle(${a.name})'),
      ),
    ),
  ),

  // ── Settings ──────────────────────────────────────────────────────────────
  GalleryEntry(
    name: 'DiscoveredQuarkList',
    group: 'Settings',
    build: (context, log) => DiscoveredQuarkList(
      quarks: const [
        HostItem(name: 'Quark on quark', address: 'https://quark.local'),
        HostItem(name: 'Quark on quark-2', address: 'https://quark-2.local'),
      ],
      isLoading: true,
      onSelect: (quark) =>
          log('DiscoveredQuarkList.onSelect(${quark.address})'),
    ),
  ),
  GalleryEntry(
    name: 'SshAccessPanel',
    group: 'Settings',
    build: (context, log) => Column(
      children: [
        SshAccessPanel(
          enabled: true,
          keys: _gallerySshKeys,
          onEnabledChanged: (on) => log('SshAccessPanel.onEnabledChanged($on)'),
          onAddKey: () => log('SshAccessPanel.onAddKey'),
          onRemoveKey: (fingerprint) =>
              log('SshAccessPanel.onRemoveKey($fingerprint)'),
          onSetPassword: () => log('SshAccessPanel.onSetPassword'),
          onClearPassword: () => log('SshAccessPanel.onClearPassword'),
        ),
        const Divider(),
        const SshAccessPanel(
          unavailableReason:
              "Quark's SSH helper isn't installed yet. On the device, run "
              '`sudo quark install` to add it.',
        ),
      ],
    ),
  ),

  // ── Storage ───────────────────────────────────────────────────────────────
  GalleryEntry(
    name: 'UploadTargetPicker',
    group: 'Storage',
    build: (context, log) => UploadTargetPicker(
      targets: _galleryTargets,
      selected: _galleryTargets.first,
      onSelected: (t) => log('UploadTargetPicker.onSelected(${t.name})'),
      onCancel: () => log('UploadTargetPicker.onCancel'),
      onConfirm: () => log('UploadTargetPicker.onConfirm'),
    ),
  ),

  // ── Users ─────────────────────────────────────────────────────────────────
  GalleryEntry(
    name: 'UserList',
    group: 'Users',
    build: (context, log) => UserList(
      users: const [
        UserAccountItem(username: 'ada', isAdmin: true),
        UserAccountItem(username: 'grace', isAdmin: true),
        UserAccountItem(username: 'bob'),
        UserAccountItem(username: 'cy', status: UserAccountStatus.disabled),
      ],
      selfUsername: 'ada',
      onPromote: (username) => log('UserList.onPromote($username)'),
      onDemote: (username) => log('UserList.onDemote($username)'),
      onDisable: (username) => log('UserList.onDisable($username)'),
      onEnable: (username) => log('UserList.onEnable($username)'),
      onDelete: (username) => log('UserList.onDelete($username)'),
    ),
  ),
  GalleryEntry(
    name: 'PendingRequestList',
    group: 'Users',
    build: (context, log) => PendingRequestList(
      requests: const [
        UserAccountItem(username: 'dee', status: UserAccountStatus.pending),
        UserAccountItem(username: 'eli', status: UserAccountStatus.pending),
      ],
      busyUsernames: const {'eli'},
      onApprove: (username) => log('PendingRequestList.onApprove($username)'),
      onDeny: (username) => log('PendingRequestList.onDeny($username)'),
    ),
  ),
  GalleryEntry(
    name: 'AccessRequestsTile',
    group: 'Users',
    build: (context, log) => AccessRequestsTile(
      enabled: true,
      onChanged: (enabled) => log('AccessRequestsTile.onChanged($enabled)'),
    ),
  ),
  GalleryEntry(
    name: 'CreateUserDialog',
    group: 'Users',
    build: (context, log) => CreateUserDialog(
      onSubmit: (input) => log('CreateUserDialog.onSubmit(${input.username})'),
      onCancel: () => log('CreateUserDialog.onCancel'),
    ),
  ),
  GalleryEntry(
    name: 'GroupList',
    group: 'Users',
    build: (context, log) => GroupList(
      groups: const [
        GroupItem(id: 1, name: 'everyone', isBuiltin: true),
        GroupItem(
          id: 2,
          name: 'Family',
          members: [
            PrincipalItem(kind: PrincipalKind.user, id: 1, name: 'ada'),
            PrincipalItem(kind: PrincipalKind.user, id: 2, name: 'bob'),
          ],
        ),
        GroupItem(id: 3, name: 'Book club'),
      ],
      onCreate: () => log('GroupList.onCreate'),
      onMembers: (id) => log('GroupList.onMembers($id)'),
      onRename: (id) => log('GroupList.onRename($id)'),
      onDelete: (id) => log('GroupList.onDelete($id)'),
    ),
  ),
  GalleryEntry(
    name: 'PrincipalPicker',
    group: 'Users',
    build: (context, log) => PrincipalPicker(
      options: const [
        PrincipalItem(
          kind: PrincipalKind.group,
          id: 1,
          name: 'everyone',
          isBuiltin: true,
        ),
        PrincipalItem(kind: PrincipalKind.group, id: 2, name: 'Family'),
        PrincipalItem(kind: PrincipalKind.user, id: 1, name: 'ada'),
        PrincipalItem(kind: PrincipalKind.user, id: 2, name: 'bob'),
      ],
      selected: const PrincipalItem(
        kind: PrincipalKind.group,
        id: 2,
        name: 'Family',
      ),
      onSelected: (principal) =>
          log('PrincipalPicker.onSelected(${principal.keySuffix})'),
    ),
  ),
  GalleryEntry(
    name: 'GroupMembersSheet',
    group: 'Users',
    build: (context, log) => GroupMembersSheet(
      group: const GroupItem(
        id: 2,
        name: 'Family',
        members: [
          PrincipalItem(kind: PrincipalKind.user, id: 1, name: 'ada'),
          PrincipalItem(kind: PrincipalKind.user, id: 2, name: 'bob'),
        ],
      ),
      candidates: const [
        PrincipalItem(kind: PrincipalKind.user, id: 1, name: 'ada'),
        PrincipalItem(kind: PrincipalKind.user, id: 2, name: 'bob'),
        PrincipalItem(kind: PrincipalKind.user, id: 3, name: 'cy'),
        PrincipalItem(kind: PrincipalKind.user, id: 4, name: 'dee'),
      ],
      busyIds: const {2},
      onAdd: (userId) => log('GroupMembersSheet.onAdd($userId)'),
      onRemove: (userId) => log('GroupMembersSheet.onRemove($userId)'),
    ),
  ),
  GalleryEntry(
    name: 'QuarkNameDialog',
    group: 'Core',
    build: (context, log) => QuarkNameDialog(
      title: 'Rename Family',
      label: 'Group name',
      submitLabel: 'Rename',
      initialName: 'Family',
      maxLength: 64,
      onSubmit: (name) => log('QuarkNameDialog.onSubmit($name)'),
      onCancel: () => log('QuarkNameDialog.onCancel'),
    ),
  ),

  // ── Sharing ───────────────────────────────────────────────────────────────
  GalleryEntry(
    name: 'ShareSheet',
    group: 'Sharing',
    build: (context, log) => ShareSheet(
      itemName: 'Recipes',
      grants: const [
        GrantItem(
          principal: PrincipalItem(
            kind: PrincipalKind.group,
            id: 1,
            name: 'everyone',
            isBuiltin: true,
          ),
          level: AccessLevel.read,
        ),
        GrantItem(
          principal: PrincipalItem(
            kind: PrincipalKind.user,
            id: 1,
            name: 'ada',
          ),
          level: AccessLevel.owner,
        ),
        GrantItem(
          principal: PrincipalItem(
            kind: PrincipalKind.user,
            id: 2,
            name: 'bob',
          ),
          level: AccessLevel.write,
        ),
        GrantItem(
          principal: PrincipalItem(
            kind: PrincipalKind.group,
            id: 2,
            name: 'Family',
          ),
          level: AccessLevel.write,
          inheritedFrom: 'Shared',
        ),
      ],
      principals: const [
        PrincipalItem(
          kind: PrincipalKind.group,
          id: 1,
          name: 'everyone',
          isBuiltin: true,
        ),
        PrincipalItem(kind: PrincipalKind.group, id: 2, name: 'Family'),
        PrincipalItem(kind: PrincipalKind.user, id: 1, name: 'ada'),
        PrincipalItem(kind: PrincipalKind.user, id: 2, name: 'bob'),
        PrincipalItem(kind: PrincipalKind.user, id: 3, name: 'cy'),
      ],
      canManage: true,
      canGrantOwner: true,
      lockedKeys: const {'user_1'},
      onAdd: (principal, level) =>
          log('ShareSheet.onAdd(${principal.keySuffix}, ${level.name})'),
      onSetLevel: (principal, level) =>
          log('ShareSheet.onSetLevel(${principal.keySuffix}, ${level.name})'),
      onRevoke: (principal) =>
          log('ShareSheet.onRevoke(${principal.keySuffix})'),
    ),
  ),

  // ── Sheets ────────────────────────────────────────────────────────────────
  GalleryEntry(
    name: 'SheetTabStrip',
    group: 'Sheets',
    build: (context, log) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTabStrip(
          tabNames: const [
            'Sheet 1',
            'Budget',
            'A very long quarterly summary',
          ],
          selectedIndex: 1,
          onSelect: (index) => log('SheetTabStrip.onSelect($index)'),
          onAdd: () => log('SheetTabStrip.onAdd'),
          onRename: (index) => log('SheetTabStrip.onRename($index)'),
          onDuplicate: (index) => log('SheetTabStrip.onDuplicate($index)'),
          onMoveLeft: (index) => log('SheetTabStrip.onMoveLeft($index)'),
          onMoveRight: (index) => log('SheetTabStrip.onMoveRight($index)'),
          onDelete: (index) => log('SheetTabStrip.onDelete($index)'),
        ),
        const SizedBox(height: 16),
        // A 64-sheet workbook with the last sheet selected, scrolled into view.
        SheetTabStrip(
          tabNames: [for (var i = 1; i <= 64; i++) 'Sheet $i'],
          selectedIndex: 63,
          onSelect: (index) => log('SheetTabStrip.onSelect($index)'),
          onAdd: () => log('SheetTabStrip.onAdd'),
          onRename: (index) => log('SheetTabStrip.onRename($index)'),
          onDuplicate: (index) => log('SheetTabStrip.onDuplicate($index)'),
          onMoveLeft: (index) => log('SheetTabStrip.onMoveLeft($index)'),
          onMoveRight: (index) => log('SheetTabStrip.onMoveRight($index)'),
          onDelete: (index) => log('SheetTabStrip.onDelete($index)'),
        ),
      ],
    ),
  ),

  // ── Video─────────────────────────────────────────────────────────────────
  GalleryEntry(
    name: 'TranscodeDialog',
    group: 'Video',
    build: (context, log) => TranscodeDialog(
      formats: const [
        TranscodeFormatOption(format: 'mp4', label: 'MP4'),
        TranscodeFormatOption(format: 'mov', label: 'MOV'),
        TranscodeFormatOption(format: 'mkv', label: 'MKV'),
        TranscodeFormatOption(format: 'webm', label: 'WebM'),
        TranscodeFormatOption(format: 'avi', label: 'AVI'),
      ],
      sourceFormat: 'mov',
      onConvert: (format, quality) =>
          log('TranscodeDialog.onConvert($format, ${quality.name})'),
      onCancel: () => log('TranscodeDialog.onCancel'),
      onRetry: () => log('TranscodeDialog.onRetry'),
    ),
  ),
];

/// The fake photo categories the photo entries share.
const List<PhotoCategoryEntry> _galleryCategories = [
  PhotoCategoryEntry(
    id: 'all',
    label: 'All',
    count: 142,
    icon: QuarkIcons.photo_library,
  ),
  PhotoCategoryEntry(
    id: 'quark',
    label: 'Quark',
    count: 128,
    icon: QuarkIcons.cloud,
  ),
  PhotoCategoryEntry(
    id: 'mobile',
    label: 'Mobile',
    count: 14,
    icon: QuarkIcons.smartphone,
  ),
  PhotoCategoryEntry(
    id: 'favorites',
    label: 'Favorites',
    count: 9,
    icon: QuarkIcons.star_rounded,
  ),
];

/// The fake album tree the album entries share: a system album, then a user
/// album with sub-albums.
const List<AlbumItem> _galleryAlbumList = [
  AlbumItem(
    id: 1,
    name: 'Favorites',
    itemCount: 9,
    isSystem: true,
    isFavorites: true,
  ),
  AlbumItem(id: 2, name: 'Recently added', itemCount: 30, isSystem: true),
  AlbumItem(
    id: 3,
    name: 'Trips',
    itemCount: 128,
    children: [
      AlbumItem(id: 4, name: 'Iceland', parentId: 3, itemCount: 40),
      AlbumItem(id: 5, name: 'Japan', parentId: 3, itemCount: 88),
    ],
  ),
];

/// The fake upload targets: the built-in disk and a plugged-in drive.
const List<UploadTarget> _galleryTargets = [
  UploadTarget(serial: '', name: '', mountPoint: '/data', isInternal: true),
  UploadTarget(serial: 'usb-1', name: 'Backup drive', mountPoint: '/mnt/usb'),
];

/// The fake SSH keys: one with a comment, one without.
const List<SshKeyItem> _gallerySshKeys = [
  SshKeyItem(
    fingerprint: 'SHA256:4mKq0mB3fY3x9vX1nC8o2wz3d5b7h1QeRk9ZcTt0aLs',
    type: 'ssh-ed25519',
    comment: 'me@laptop',
  ),
  SshKeyItem(
    fingerprint: 'SHA256:Zp1yF0vH8wQ2c5nKj7rT3xB9mLd4sAe6gUo1iVb2hNk',
    type: 'ssh-rsa',
  ),
];

/// The fake jobs: one of every state the list draws.
const List<JobItem> _galleryJobs = [
  JobItem(
    id: 4,
    name: 'Convert vacation.mkv to MOV',
    status: JobItemStatus.running,
    progress: 0.45,
    attempts: 1,
    elapsed: Duration(seconds: 83),
    canCancel: true,
  ),
  JobItem(
    id: 3,
    name: 'Convert clip.avi to MP4',
    status: JobItemStatus.running,
    progress: 0.9,
    attempts: 1,
    elapsed: Duration(seconds: 4),
    isQuickCopy: true,
    canCancel: true,
  ),
  JobItem(
    id: 2,
    name: 'Convert party.mov to MP4',
    status: JobItemStatus.pending,
    canCancel: true,
  ),
  JobItem(
    id: 1,
    name: 'Convert old.wmv to MP4',
    status: JobItemStatus.failed,
    attempts: 2,
    elapsed: Duration(minutes: 12, seconds: 5),
    canRetry: true,
  ),
  JobItem(
    id: 0,
    name: 'Convert birthday.mkv to MP4',
    status: JobItemStatus.completed,
    progress: 1,
    attempts: 1,
    elapsed: Duration(hours: 1, minutes: 2, seconds: 3),
  ),
];
