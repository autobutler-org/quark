import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

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
    build: (context, log) => const PasswordStrengthDemo(),
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

  // ── Layout ────────────────────────────────────────────────────────────────
  GalleryEntry(
    name: 'QuarkAppBar',
    group: 'Layout',
    build: (context, log) => SizedBox(
      height: 360,
      child: Scaffold(
        appBar: QuarkAppBar(
          label: 'Photos',
          icon: QuarkIcons.photo_library_outlined,
          actions: [
            RefreshIconButton(
              isRefreshing: false,
              onPressed: () => log('QuarkAppBar refresh'),
            ),
            ThemeToggleButton(
              mode: ThemeMode.dark,
              onChanged: (mode) => log('ThemeToggleButton.onChanged($mode)'),
            ),
          ],
        ),
        drawer: QuarkDrawer(
          activeSection: QuarkDrawerSection.photos,
          onTapFiles: () => log('QuarkDrawer files'),
        ),
        body: const Center(child: Text('Tap the brand button')),
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
        onTapFiles: () => log('QuarkDrawer.onTapFiles'),
        onTapPhotos: () => log('QuarkDrawer.onTapPhotos'),
        onTapDocs: () => log('QuarkDrawer.onTapDocs'),
        onTapSheets: () => log('QuarkDrawer.onTapSheets'),
        onTapDevices: () => log('QuarkDrawer.onTapDevices'),
        onTapHealth: () => log('QuarkDrawer.onTapHealth'),
        onTapVault: () => log('QuarkDrawer.onTapVault'),
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
        actions: [
          RefreshIconButton(
            isRefreshing: false,
            onPressed: () => log('QuarkPageScaffold refresh'),
          ),
        ],
        drawer: QuarkDrawer(
          activeSection: QuarkDrawerSection.photos,
          onTapFiles: () => log('QuarkDrawer.onTapFiles'),
        ),
        bottomBar: PhotoSelectionBar(
          selectedCount: 3,
          onAddToAlbum: () => log('PhotoSelectionBar.onAddToAlbum'),
          onCancel: () => log('PhotoSelectionBar.onCancel'),
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
    build: (context, log) => FileSelectionBar(
      selectedCount: 2,
      totalCount: 7,
      onSelectAll: () => log('FileSelectionBar.onSelectAll'),
      onDeselectAll: () => log('FileSelectionBar.onDeselectAll'),
      onCancel: () => log('FileSelectionBar.onCancel'),
      onDelete: () => log('FileSelectionBar.onDelete'),
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

  // ── Photos ────────────────────────────────────────────────────────────────
  GalleryEntry(
    name: 'PhotoSelectionBar',
    group: 'Photos',
    build: (context, log) => Column(
      children: [
        PhotoSelectionBar(
          selectedCount: 3,
          onAddToAlbum: () => log('PhotoSelectionBar.onAddToAlbum'),
          onCancel: () => log('PhotoSelectionBar.onCancel'),
        ),
        const SizedBox(height: 16),
        PhotoSelectionBar(
          selectedCount: 0,
          onAddToAlbum: () => log('never called'),
          onCancel: () => log('PhotoSelectionBar.onCancel'),
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

  // ── Albums ────────────────────────────────────────────────────────────────
  GalleryEntry(
    name: 'AlbumTreeTile',
    group: 'Albums',
    build: (context, log) => AlbumTreeDemo(log: log),
  ),
];
