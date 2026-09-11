/// What the docs editor should do about a paste the user just asked for
/// (#1857).
///
/// Pasting has two ways of silently doing nothing, and neither tells the user
/// anything:
///
/// - **The document is read-only.** `QuillController.clipboardPaste` opens
///   with `if (readOnly || !selection.isValid) return true;`, so Ctrl/Cmd+V
///   before the document is in edit mode is swallowed whole. Docs open
///   read-only (#939).
/// - **The browser will not share the clipboard.** Reading it needs a secure
///   context, and a self-hosted Quark reached at `http://192.168.x.x` is not
///   one: `navigator.clipboard` is simply absent, flutter_quill's rich-paste
///   path finds no HTML and no markdown, and the plain-text fallback throws
///   where nothing catches it. Copying is unaffected — the browser keeps a
///   fallback for *writing* the clipboard — which is why a report of "copy
///   and paste are broken" can turn out to be about paste alone.
enum DocumentPasteAction {
  /// The clipboard is out of reach; say so rather than doing nothing.
  unavailable,

  /// Start editing first, then paste — a paste is an edit, and asking for one
  /// says plainly enough that the reader wants to become a writer.
  editThenPaste,

  /// Nothing in the way: let flutter_quill paste as it normally would.
  passThrough,
}

/// Decides between them. [clipboardAvailable] comes from
/// `isClipboardAvailable` in `clipboard_utils.dart`, which is `true`
/// everywhere but an insecure web context.
DocumentPasteAction documentPasteAction({
  required bool clipboardAvailable,
  required bool isReadOnly,
}) {
  if (!clipboardAvailable) return DocumentPasteAction.unavailable;
  if (isReadOnly) return DocumentPasteAction.editThenPaste;
  return DocumentPasteAction.passThrough;
}
