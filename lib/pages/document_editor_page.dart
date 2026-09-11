import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill_to_pdf/flutter_quill_to_pdf.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';
import 'package:quark/router.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_browser_path_utils.dart';
import 'package:quark/utils/files_route_path_utils.dart';
import 'package:quark/widgets/document_editor/document_editor_body.dart';
import 'package:quark/widgets/document_editor/highlight_picker_dialog.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Find shortcut ─────────────────────────────────────────────────────────────

/// Swallows Ctrl/Cmd+F inside a [QuillEditor] and runs [onToggle] instead.
///
/// flutter_quill binds Ctrl/Cmd+F to its own modal search dialog
/// (`OpenSearchIntent`), which would open on top of our inline find bar. A
/// `customShortcuts` entry does win today, but only by accident:
/// `SingleActivator` compares by identity, so the caller's entry and the
/// package's non-const default never collide in the merged map and ours is
/// simply found first. That is an implementation detail, not a documented
/// contract, so this hangs off `onKeyPressed`, which runs on the editor's own
/// focus node before any `Shortcuts` layer and does not depend on map
/// ordering. Returning a non-null result stops the event there (#1046).
///
/// Returns null for anything else so flutter_quill handles keys as usual.
KeyEventResult? quillFindKeyInterceptor(KeyEvent event, VoidCallback onToggle) {
  if (event.logicalKey != LogicalKeyboardKey.keyF) return null;
  final modified =
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed;
  if (!modified) return null;
  if (event is KeyDownEvent) onToggle();
  return KeyEventResult.handled;
}

// ── Page ──────────────────────────────────────────────────────────────────────

class DocumentEditorPage extends StatefulWidget {
  final String filePath;
  final String deviceSerial;
  final String? overlayTargetRoute;
  final String? overlayCloseRoute;

  /// Opens ready to type instead of read-only. Set by the create flows: a
  /// document the user just made has nothing to read yet (#1568).
  final bool startInEditMode;

  const DocumentEditorPage({
    required this.filePath,
    this.deviceSerial = '',
    this.overlayTargetRoute,
    this.overlayCloseRoute,
    this.startInEditMode = false,
    super.key,
  });

  @override
  State<DocumentEditorPage> createState() => _DocumentEditorPageState();
}

class _DocumentEditorPageState extends State<DocumentEditorPage> {
  late QuillController _controller;
  final FocusNode _editorFocus = FocusNode();
  final ScrollController _scrollController = ScrollController();

  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  bool _exporting = false;

  /// The thrown object, not its message — the render decides whether it means
  /// "your Quark is unreachable" or "the request failed" (#1637).
  Object? _error;
  bool _routeMovedExternally = false;

  // Read-only / edit mode (#939)
  late bool _isReadOnly = !widget.startInEditMode;

  // Edit button glow hint (#940)
  bool _hintEditButton = false;
  Timer? _hintTimer;

  // Dark page mode (#938)
  static const _prefKeyDarkPage = 'document_editor_dark_page';
  bool _editorDarkPage = false;

  // Auto-save
  static const _prefKeyAutoSave = 'document_editor_auto_save';
  static const _autoSaveDelay = Duration(seconds: 2);
  bool _autoSaveEnabled = true;
  Timer? _autoSaveTimer;

  // Word count. `toPlainText()` walks the whole document, so it is recomputed
  // on a debounce and published through a notifier — the count changing
  // rebuilds the status bar rather than the whole page (#1816).
  static const _wordCountDelay = Duration(milliseconds: 300);
  final ValueNotifier<int> _wordCount = ValueNotifier(0);
  Timer? _wordCountTimer;
  StreamSubscription<DocChange>? _docChanges;

  // In-document find bar (#1046)
  bool _showFindBar = false;

  late String _displayName;

  @override
  void initState() {
    super.initState();
    _displayName = _nameFromPath(widget.filePath);
    _controller = QuillController.basic()..readOnly = _isReadOnly;
    if (widget.overlayTargetRoute != null) {
      router.routeInformationProvider.addListener(_handleOverlayRouteChange);
    }
    _loadPrefs();
    _loadDocument();
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _hintTimer?.cancel();
    _wordCountTimer?.cancel();
    _docChanges?.cancel();
    _wordCount.dispose();
    if (widget.overlayTargetRoute != null) {
      router.routeInformationProvider.removeListener(_handleOverlayRouteChange);
    }
    _controller.dispose();
    _editorFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _nameFromPath(String path) => fileNameWithoutExtension(path, '.qdoc');

  /// The live location, canonicalized. go_router always reports it
  /// percent-encoded while `overlayTargetRoute` is built from the raw path, so
  /// comparing the two directly reported "moved externally" for every file
  /// whose name needed encoding — a space being the common case — and popped
  /// the editor the instant it opened (#1604).
  String _currentRoute() => AppRoutes.canonicalRoute(
    router.routeInformationProvider.value.uri.toString(),
  );

  bool _isOnRoute(String route) =>
      _currentRoute() == AppRoutes.canonicalRoute(route);

  Future<void> _handleOverlayRouteChange() async {
    final targetRoute = widget.overlayTargetRoute;
    if (targetRoute == null || !mounted || _isOnRoute(targetRoute)) {
      return;
    }

    _routeMovedExternally = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      await Navigator.of(context).maybePop();
    });
  }

  /// The editor's own way out when nothing was pushed underneath it.
  ///
  /// [AppBar] implies a back button only when the navigator can pop, so a doc
  /// reached by deep link or a pasted URL had no way out at all except the
  /// browser's, which walked to whatever sat before the app. Returning null
  /// leaves every other entry point — the docs list, a search hit, the file
  /// browser's overlay — on the implied button, and their existing pop
  /// handling (#1749).
  Widget? _backButton() => Navigator.of(context).canPop()
      ? null
      : BackButton(onPressed: _leaveForContainingFolder);

  /// Closes a doc that has no history behind it, landing in the folder that
  /// holds it rather than the home folder.
  Future<void> _leaveForContainingFolder() async {
    if (_dirty && !await _confirmDiscard(context)) {
      return;
    }
    if (!mounted) return;
    context.go(AppRoutes.containingFolder(widget.filePath));
  }

  void _restoreOverlayCloseRoute() {
    final targetRoute = widget.overlayTargetRoute;
    final closeRoute = widget.overlayCloseRoute;
    if (targetRoute == null || closeRoute == null) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_routeMovedExternally && _isOnRoute(targetRoute)) {
        router.go(closeRoute);
      }
    });
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _autoSaveEnabled = prefs.getBool(_prefKeyAutoSave) ?? true;
      _editorDarkPage = prefs.getBool(_prefKeyDarkPage) ?? false;
    });
  }

  Future<void> _setAutoSaveEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeyAutoSave, value);
    if (!mounted) return;
    setState(() => _autoSaveEnabled = value);
    if (!value) {
      _autoSaveTimer?.cancel();
      _autoSaveTimer = null;
    }
  }

  // ── Read-only / edit toggle (#939) ────────────────────────────────────────

  void _enterEditMode() {
    _controller.readOnly = false;
    setState(() => _isReadOnly = false);
    _focusEditor();
  }

  Future<void> _exitEditMode() async {
    _controller.readOnly = true;
    setState(() => _isReadOnly = true);
    _editorFocus.unfocus();
    if (_dirty) {
      _autoSaveTimer?.cancel();
      await _autoSaveSilently();
    }
  }

  // ── Edit button glow hint (#940) ──────────────────────────────────────────

  void _onEditorTappedInReadOnly() {
    if (!_isReadOnly) return;
    _hintTimer?.cancel();
    setState(() => _hintEditButton = true);
    _hintTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _hintEditButton = false);
    });
  }

  // ── Document ───────────────────────────────────────────────────────────────

  Future<void> _loadDocument() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final bytes = await FilesService.downloadFileBytes(
        widget.filePath,
        serial: serialOrNull(widget.deviceSerial),
      );

      if (!mounted) return;

      if (bytes == null || bytes.isEmpty) {
        setState(() {
          _loading = false;
          _dirty = false;
        });
        _listenForEdits();
        if (!_isReadOnly) _focusEditor();
        return;
      }

      final jsonString = utf8.decode(bytes);
      final jsonData = jsonDecode(jsonString) as Map<String, dynamic>?;

      Document doc;
      if (jsonData != null && jsonData['ops'] is List) {
        doc = Document.fromJson(jsonData['ops'] as List);
      } else {
        doc = Document();
      }

      if (!mounted) return;
      final controller = QuillController(
        document: doc,
        selection: const TextSelection.collapsed(offset: 0),
      );
      controller.readOnly = _isReadOnly;
      setState(() {
        _controller = controller;
        _loading = false;
        _dirty = false;
      });
      _wordCount.value = _countWords(doc.toPlainText());
      _listenForEdits();
      if (!_isReadOnly) _focusEditor();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  void _focusEditor() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FocusScope.of(context).unfocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _editorFocus.requestFocus();
      });
    });
  }

  int _countWords(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return 0;
    return trimmed.split(RegExp(r'\s+')).length;
  }

  /// Subscribes to document edits only.
  ///
  /// [QuillController] notifies on every change it knows about, caret and
  /// selection moves included, so listening to the controller re-ran the word
  /// count on every arrow key (#1816). The document's own stream carries edits
  /// and nothing else.
  void _listenForEdits() {
    _docChanges?.cancel();
    _docChanges = _controller.document.changes.listen(
      (_) => _onDocumentChanged(),
    );
  }

  void _onDocumentChanged() {
    if (!mounted) return;
    // Do not mark dirty or schedule auto-save in read-only mode
    if (_isReadOnly) return;
    if (!_dirty) setState(() => _dirty = true);
    _wordCountTimer?.cancel();
    _wordCountTimer = Timer(_wordCountDelay, _recountWords);
    if (_autoSaveEnabled) {
      _autoSaveTimer?.cancel();
      _autoSaveTimer = Timer(_autoSaveDelay, _autoSaveSilently);
    }
  }

  void _recountWords() {
    if (!mounted) return;
    _wordCount.value = _countWords(_controller.document.toPlainText());
  }

  Future<void> _autoSaveSilently() async {
    if (!_dirty || _saving || !mounted) return;
    try {
      await _doSave();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(Errors.message(e, 'auto-save')),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _saveDocument() async {
    _autoSaveTimer?.cancel();
    try {
      await _doSave();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saved')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Errors.message(e, 'save the document'))),
      );
    }
  }

  Future<void> _doSave() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final ops = _controller.document.toDelta().toJson();
      final bytes = utf8.encode(jsonEncode({'ops': ops}));
      final fileName = '$_displayName.qdoc';
      final parentDir = parentPath(widget.filePath);
      final serial = serialOrNull(widget.deviceSerial);
      final file = http.MultipartFile.fromBytes(
        'files',
        bytes,
        filename: fileName,
      );
      await FilesService.uploadFilesFromFormData(
        parentDir,
        [file],
        serial: serial,
        overwrite: true,
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _dirty = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      rethrow;
    }
  }

  // ── PDF / Print ────────────────────────────────────────────────────────────

  Future<Uint8List?> _buildPdfBytes() async {
    final converter = PDFConverter(
      document: _controller.document.toDelta(),
      pageFormat: PDFPageFormat.a4,
      fallbacks: const [],
      // ignore: experimental_member_use
      isWeb: kIsWeb,
    );
    final doc = await converter.createDocument();
    return doc?.save();
  }

  Future<void> _exportPdf() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final bytes = await _buildPdfBytes();
      if (!mounted) return;
      if (bytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Errors.couldNot('export the document'))),
        );
        return;
      }
      await Printing.sharePdf(bytes: bytes, filename: '$_displayName.pdf');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Errors.message(e, 'export the document'))),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _printDocument() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final bytes = await _buildPdfBytes();
      if (!mounted) return;
      if (bytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Errors.couldNot('print the document'))),
        );
        return;
      }
      await Printing.layoutPdf(onLayout: (_) => bytes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Errors.message(e, 'print the document'))),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) {
          _restoreOverlayCloseRoute();
          return;
        }
        final leave = await _confirmDiscard(context);
        if (!context.mounted) {
          return;
        }
        if (leave) {
          Navigator.of(context).pop();
          return;
        }
        if (_routeMovedExternally && widget.overlayTargetRoute != null) {
          _routeMovedExternally = false;
          router.go(widget.overlayTargetRoute!);
        }
      },
      child: CallbackShortcuts(
        bindings: {
          // Ctrl+F / Cmd+F — toggle find bar (#1046). Only fires when focus is
          // outside the editor; the editor handles it in _handleEditorKey.
          const SingleActivator(LogicalKeyboardKey.keyF, control: true):
              _toggleFindBar,
          const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
              _toggleFindBar,
          // Escape — close find bar when open
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (_showFindBar) setState(() => _showFindBar = false);
          },
        },
        child: Focus(
          // Take focus on open so Ctrl+F reaches CallbackShortcuts before the
          // user has clicked into the editor (which never autofocuses).
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(
              leading: _backButton(),
              title: Text(_dirty ? '$_displayName •' : _displayName),
              actions: _buildAppBarActions(context),
            ),
            body: DocumentEditorBody(
              loading: _loading,
              error: _error,
              onRetry: _loadDocument,
              controller: _controller,
              editorFocus: _editorFocus,
              scrollController: _scrollController,
              isReadOnly: _isReadOnly,
              showFindBar: _showFindBar,
              onToggleFindBar: _toggleFindBar,
              onPickBackgroundColor: _pickBackgroundColor,
              darkPage: _editorDarkPage,
              onToggleDarkPage: _toggleDarkPage,
              onEditorTap: _onEditorTappedInReadOnly,
              onEditorKey: _handleEditorKey,
              wordCount: _wordCount,
              dirty: _dirty,
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildAppBarActions(BuildContext context) {
    return [
      // In-document find bar (#1046)
      IconButton(
        icon: Icon(_showFindBar ? Icons.close : QuarkIcons.search_rounded),
        tooltip: _showFindBar ? 'Close find bar' : 'Find in document (Ctrl+F)',
        onPressed: _toggleFindBar,
      ),
      // Settings shortcut
      IconButton(
        icon: const Icon(QuarkIcons.settings_outlined),
        tooltip: 'Settings',
        onPressed: () => context.go(AppRoutes.settings),
      ),
      const AppThemeToggle(),
      // Auto-save toggle (only relevant in edit mode)
      if (!_isReadOnly)
        IconButton(
          icon: Icon(
            _autoSaveEnabled
                ? QuarkIcons.cloud_sync_outlined
                : QuarkIcons.cloud_off_outlined,
          ),
          tooltip: _autoSaveEnabled ? 'Auto-save on' : 'Auto-save off',
          onPressed: () => _setAutoSaveEnabled(!_autoSaveEnabled),
        ),
      // Overflow menu
      if (_exporting)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        )
      else
        IconButton(
          icon: const Icon(QuarkIcons.more_horiz),
          tooltip: 'More options',
          onPressed: () => _showOverflowMenu(context),
        ),
      // Save button (only in edit mode)
      if (!_isReadOnly)
        if (_saving)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: FilledButton.icon(
              onPressed: _dirty ? _saveDocument : null,
              icon: const Icon(QuarkIcons.save_outlined, size: 16),
              label: const Text('Save'),
            ),
          ),
      // Edit / Done toggle button (#939) with glow hint (#940)
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: _hintEditButton
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.6),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                )
              : null,
          child: _isReadOnly
              ? FilledButton.icon(
                  onPressed: _enterEditMode,
                  icon: const Icon(QuarkIcons.edit_outlined, size: 16),
                  label: const Text('Edit'),
                )
              : OutlinedButton.icon(
                  onPressed: _exitEditMode,
                  icon: const Icon(QuarkIcons.check, size: 16),
                  label: const Text('Done'),
                ),
        ),
      ),
    ];
  }

  void _showOverflowMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outline,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(QuarkIcons.picture_as_pdf_outlined),
            title: const Text('Export as PDF'),
            onTap: () {
              Navigator.pop(context);
              _exportPdf();
            },
          ),
          ListTile(
            leading: const Icon(QuarkIcons.print_outlined),
            title: const Text('Print'),
            onTap: () {
              Navigator.pop(context);
              _printDocument();
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _toggleFindBar() => setState(() => _showFindBar = !_showFindBar);

  Future<void> _toggleDarkPage() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _editorDarkPage = !_editorDarkPage);
    await prefs.setBool(_prefKeyDarkPage, _editorDarkPage);
  }

  KeyEventResult? _handleEditorKey(KeyEvent event, Node? node) =>
      quillFindKeyInterceptor(event, _toggleFindBar);

  Future<void> _pickBackgroundColor(
    QuillController controller,
    bool isBackground,
  ) async {
    if (!mounted) return;
    // Save selection before the dialog steals focus (web loses it otherwise).
    final saved = controller.selection;

    final picked = await showDialog<Color?>(
      context: context,
      builder: (_) => const HighlightPickerDialog(),
    );

    if (!mounted) return;
    if (picked == null) return; // cancelled

    // Restore selection in case web dropped it while the dialog was open.
    if (saved.isValid) {
      controller.updateSelection(saved, ChangeSource.local);
    }

    // Always clear first so we never visually stack two background colors.
    controller.formatSelection(const BackgroundAttribute(null));
    if (picked != Colors.transparent) {
      controller.formatSelection(BackgroundAttribute(_colorToHex(picked)));
    }
  }

  Future<bool> _confirmDiscard(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: const Text('You have unsaved changes. Leave without saving?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

// Produces "#AARRGGBB" matching flutter_quill's BackgroundAttribute storage format.
String _colorToHex(Color color) {
  int ch(double v) => (v * 255).round() & 0xFF;
  return '#'
          '${ch(color.a).toRadixString(16).padLeft(2, '0')}'
          '${ch(color.r).toRadixString(16).padLeft(2, '0')}'
          '${ch(color.g).toRadixString(16).padLeft(2, '0')}'
          '${ch(color.b).toRadixString(16).padLeft(2, '0')}'
      .toUpperCase();
}
