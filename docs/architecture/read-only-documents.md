# Read-only documents: DOCX, ODT, RTF, Markdown, PPTX/ODP, ODS/XLS

**Status: proposal; the readers and the document viewer have landed, the other viewers have not.** Built:
Markdown (#3175), the office zip reader, the DOCX and DOCM reader, ODT, RTF, ODS, legacy XLS, ODP, package-part
images in the slides package, the document and part previews API, the document view widget, and the document
viewer page at `/document/<path>` with Open as Quark doc (#3265). Not built yet: document properties in the
viewers, the presentation and workbook viewer pages, and the Markdown SVG and alert gaps. This is the design for #2987 under epic #2994. Markdown has already
shipped (#3175), so this page records that choice and does not reopen it. For everything else it sets out the
decisions that need the owner's call: where documents are parsed, how a word-processing document is drawn, how a
shared zip reader is factored, and which reader opens legacy `.xls`. It recommends one option for each, then splits
the work into sub-tickets that can land one at a time. The sub-tickets are not filed until the options are chosen.

## What the issue asks for

Common office formats open for reading without leaving Quark:

- **DOCX, ODT and RTF**, with headings, lists, tables, images and basic styles, plus an **Open as Quark doc**
  action that imports the file to `.qdoc`.
- **Markdown**, rendered, with a source toggle, relative image links, task lists and code blocks.
- **PPTX and ODP**, one slide at a time, built on `quark_slides` and `pptxutil`. This closes #196.
- **ODS and legacy XLS**, read-only in the sheets table view. Legacy `.xls` cannot be read at all today (#1741).
- **Page and word counts and document properties** in the file info panel.

The constraints come from the issue and `AGENTS.md`:

- **No LibreOffice on the device**, and nothing else installed into the OS image. Everything is parsed in pure Go
  or pure Dart.
- **Streaming and memory rules.** A 300 MB DOCX full of photographs costs the server a few megabytes of heap, and
  a file is never read whole to make it seekable.
- **Nothing a document contains is executed or fetched.** That covers macros, scripts, field codes, OLE objects,
  remote templates and linked images.
- **Ask before a new dependency or abstraction**, and never vendor or fork one. Each such decision below gives two
  or three options.

## What already exists to build on

| Piece | What it gives this work |
| ----- | ----------------------- |
| `QuarkMarkdownView`, `MarkdownViewerPage`, `/markdown/<path>` (#3175) | the shipped Markdown viewer, with Source toggle, Edit, relative links and images, and click-to-load remote images |
| `pkg/util/pptxutil` | a hardened PowerPoint reader. `ImportPptx` reads an `io.ReaderAt` in place and writes `.qslide` JSON to an `io.Writer` one slide at a time, with limits on entries, part size, XML elements, depth and media |
| `pkg/util/xlsxutil` | an OOXML workbook streamed into the `.qsheet` envelope, with limits on sheets, rows, cells and shared strings |
| `fileutil.ConvertXlsxToQsheet`, `fileutil.ImportPptx` | the "write a Quark file beside the original" service functions, events included |
| `POST /files/convert/xlsx`, `POST /files/import/pptx` | the conversion routes the client already calls |
| `fileutil` archive limits and `GET /files/download-archive-file` | zip-bomb limits for browsing archives. They are gated on `SupportedArchiveExts`, which leaves out office files on purpose |
| `SlideCanvas.readOnly`, `SlidePresentPage` | read-only slide drawing, and a full presenter |
| `lib/utils/file_kind.dart` | the client's one extension table. `fileKindForName` drives every viewer choice |
| `lib/utils/*_viewer_files.dart`, `viewFileRedirect` | the routing pattern the code, Markdown and 3D viewers use (#2991, #3175, #3238) |
| `QuarkModelViewer` (#3238) | the most recent viewer: package widget, controller, thin page, caps checked before download, falls back to the generic viewer |
| `GenericFileViewerPage` | where DOCX, PPTX, EPUB and a deep-linked XLSX land today: details, download and Open with |
| `flutter_quill`, `.qdoc` | the document editor. A `.qdoc` is `{"ops": [...]}`, a Quill Delta with no image or table embeds today |
| `iosemutil` | IO semaphore classes, `Decode` among them |

Four facts shape the design:

- `.ppt` is classified as a slideshow but nothing can read it.
- `.xlsx` opens through a "convert to `.qsheet`?" prompt, not a viewer.
- Files has no general info panel. Only photos have one, and the generic viewer shows a details list.
- The `archive` and `xml` Dart packages are already in `pubspec.lock` as transitive dependencies, as `markdown`
  was before #3175.

## Decision 0: Markdown rendering (already decided, #3175)

The issue lists Markdown first, and it was the first thing to decide because `pubspec.yaml` had no Markdown
package. #3175 settled it, and the shipped code is the record:

- **Parser:** the Dart `markdown` package (`^7.1.0`), now a direct dependency of `quark_widgets` and the only one
  it gained. It was already in the lockfile, so the lockfile did not change.
- **Renderer:** our own `QuarkMarkdownView` (`packages/quark_widgets/lib/src/markdown/`), which turns the
  package's AST into Quark widgets: headings, lists, task lists, GFM tables, highlighted code blocks, links and
  images through an `imageBuilder` slot.
- **Not chosen:** `flutter_markdown`, which pub.dev marks discontinued; its fork `flutter_markdown_plus`; and
  `markdown_widget`. Each would have been a new dependency with its own theming that does not take
  `QuarkTokens`.
- **Security as shipped:** raw HTML renders as text. Relative links resolve against the file's folder and cannot
  climb above the files root. Remote images load only after the reader taps "Load remote image". `javascript:`,
  `data:` and every other scheme do nothing.
- **Memory as shipped:** the rendered view reads at most 1 MB (`MarkdownViewerConfig.maxBytes`) and says when it
  stopped. The source view pages through the rest.

Two known gaps remain, and both are small follow-ups that need no new dependency:

- An SVG image shows its alt text, though `flutter_svg` is already an app dependency.
- GitHub `> [!NOTE]` alerts render as plain block quotes.

Both are in ticket 19.

## Decision 1: where office formats are parsed

### Option P1: Go on the server, the client renders a converted form (recommended)

Every office reader lives in `pkg/util/`. A read-only endpoint streams a converted form, which the client draws:

- `.qslide` JSON for presentations, which `pptxutil` already writes.
- The `.qsheet` envelope for workbooks, which `xlsxutil` already writes.
- A document block stream for word-processing files (Decision 2).

The reasons for P1:

- **It reads in place.** A DOCX, ODT, PPTX, ODP, XLSX or ODS is a zip, and a zip's directory is at its end. The
  server has a `vfs.File`, an `io.ReaderAt` sized by `Stat`, so it reads the directory and the parts it needs and
  nothing else. The client has an HTTP body. On the web it cannot seek and has no isolates (`compute` runs on the
  UI thread), so a Dart reader means downloading the whole file and holding it in browser memory before showing
  a page.
- **The hardened code is already here.** `pptxutil` and `xlsxutil` already enforce limits against what is
  actually read. A Dart reader would repeat that hardening in a second language.
- **Import needs the server reader anyway.** "Open as Quark doc", "Open as Quark sheet" and "Open as Quark
  slides" write a sibling file on the device, as the existing conversions do. With P1 the viewer and the import
  share one reader.
- **The client stays thin.** No new Dart dependency, and no parsing on a phone's UI thread.

What P1 costs: a viewer needs the Quark reachable, so a file inside a zip on the client cannot be previewed this
way. Archive entries already preview only images and text (`_openArchiveFile`).

### Option P2: Dart on the client, as the 3D viewer does

Make `archive` and `xml` direct dependencies and parse in Dart behind caps checked before download, as
`QuarkModelViewer` does (64 MB, then fall back to the generic viewer).

- **For it:** works for any bytes the client holds, and adds no server routes.
- **Against it:** the 3D viewer can do this because a mesh file must be downloaded whole to be drawn at all. An
  office document is mostly pictures the reader may never scroll to. A 64 MB cap would turn away ordinary
  photo-heavy reports. Import would still need a Go reader, so every format would be parsed twice, in two
  languages, with two sets of limits. Two direct dependencies.

### Option P3: both

Go for import and Dart for viewing. This is P2's duplication with no gain over P1.

**Recommendation: P1.** Markdown stays client-side, as shipped: it is plain text, already capped, and has nothing
to unzip.

## Decision 2: how a word-processing document is drawn (DOCX, ODT, RTF)

### Option R1: convert to a Quill Delta and draw it with `flutter_quill` in read-only mode

Go converts the document to a `.qdoc` Delta. The viewer is a `QuillEditor` with `readOnly: true`, and "Open as
Quark doc" saves that same Delta.

- **For it:** no new widget, and what the viewer shows is exactly what the import will produce.
- **Against it:** a Delta has no tables, and the `.qdoc` editor has no image or table embeds. Tables, one of the
  four things the issue names, would be flattened. `QuillEditor` also lays out the whole document, so a long
  report pays for every page when it opens. Images need an embed builder the editor does not have, and adding
  one changes the editor too.

### Option R2: convert to GitHub-flavored Markdown and draw it with `QuarkMarkdownView`

Go writes GFM. The client reuses the shipped Markdown viewer, with images fetched through the part endpoint
below.

- **For it:** no new widget at all, and tables, lists, images, bold, italic and strikethrough already render.
- **Against it:** Markdown has no underline, alignment or merged cells. Escaping arbitrary document text into
  Markdown is a lasting source of bugs (a heading that starts `1.`, a literal `|` inside a table cell). The view
  parses everything at once and is capped at 1 MB, which a long report can exceed in text alone.

### Option R3: a small block model, drawn by a new `QuarkDocumentView` package widget (recommended)

Go readers emit one block stream:

- headings, paragraphs and list items made of styled runs
- tables with spans
- images, page breaks, and "omitted" markers

The stream has two writers:

- **NDJSON** for the view. One block per line, so the server never builds the document in memory.
- **Delta** for "Open as Quark doc". It flattens what `.qdoc` cannot hold (tables become one line per row with
  tab-separated cells, and images are left out) and names those losses in the import's warnings.

`QuarkDocumentView` is a `ListView.builder` over the blocks, so a 500-page document lays out only what is on
screen.

- **For it:** draws all four things the issue names, and long documents stay cheap. The block stream is the one
  source of truth for view, import, and page and word counts.
- **Against it:** a new package widget set: model types, widget, parts, tests and gallery entry. Plan on roughly
  the size of `QuarkMarkdownView`. It is also a new abstraction in Go: the block types and two writers.

**Recommendation: R3.** It is the only option that draws tables without changing the `.qdoc` editor. If the owner
wants no new widget, R1 is the fallback, and it accepts flattened tables in the viewer too.

### The block stream (shape for R3)

One JSON object per line, `Content-Type: application/x-ndjson`:

```json
{"type":"meta","version":1,"format":"docx","title":"Q3 report"}
{"type":"heading","level":1,"runs":[{"text":"Summary"}]}
{"type":"paragraph","align":"justify","runs":[{"text":"Revenue "},{"text":"rose","bold":true},{"text":" again.","link":"https://example.com"}]}
{"type":"listItem","ordered":true,"level":0,"marker":"1.","runs":[{"text":"First point"}]}
{"type":"table","rows":[{"cells":[{"colSpan":2,"rowSpan":1,"blocks":[{"type":"paragraph","runs":[{"text":"Header"}]}]}]}]}
{"type":"image","part":"word/media/image1.png","alt":"Chart of revenue","width":640,"height":360}
{"type":"image","external":true,"alt":"Logo"}
{"type":"omitted","what":"embedded object"}
{"type":"pageBreak"}
{"type":"end","truncated":false,"words":1234,"characters":7020,"paragraphs":88,"warnings":["2 embedded objects not shown"]}
```

- **Runs** carry `bold`, `italic`, `underline`, `strike`, `code` (a monospace font), `superscript`, `subscript`
  and `link`. Text color, highlight and font family are dropped in v1. A document's dark-on-white colors become
  unreadable on Quark's dark theme, and `QuarkTokens` owns color. The same goes for font sizes outside the
  heading levels. This is an open question below.
- **A table cell holds blocks**, so lists and nested tables survive. Nesting is capped at 8 levels; a table nested
  deeper is flattened to paragraphs.
- **`end` is always the last line.** A stream that stops without one was cut off by a server error, and the
  client shows the error rather than a partial document. `truncated: true` means a limit was reached (see
  Memory). The view then says "Showing the first N pages", as the Markdown viewer does.
- **Only the readers define what a format contributes.** The model is not a general rich-text format, and it
  grows only when a reader needs it to.

## Decision 3: a shared bounded reader for office zips

DOCX, ODT, ODS and ODP are all zips of XML parts, and so are the PPTX and XLSX formats Quark already reads.
`pptxutil` (`import_archive.go`) and `xlsxutil` (`part.go`) each carry their own copy of "open the zip, refuse
too many entries, cap each part's decompressed size, decode XML with element and depth limits".

### Option Z1: a new `pkg/util/officezip`, used by the new readers (recommended)

One package with three pieces:

- `Open(io.ReaderAt, size, Limits) (*Package, error)`.
- `Package.Part(name)`, which returns a capped `io.ReadCloser`, and `Package.XML(name)`, which returns a token
  decoder that counts elements and depth.
- OOXML `_rels` parsing that marks `TargetMode="External"` targets, and ODF `META-INF/manifest.xml` listing.

The four new readers use it. `pptxutil` and `xlsxutil` keep their own copies until a later, separate refactor,
which is not on the ticket list. That avoids touching hardened code to build a viewer.

- **Cost:** one new internal package, and no new dependency.

### Option Z2: copy the pattern into each new reader

Nothing shared. This makes four more copies of security-critical limit code, which "Say it once" in `AGENTS.md`
argues against.

### Option Z3: Z1, and migrate `pptxutil` and `xlsxutil` onto it now

This ends with one copy, but it puts edits to two working, fuzz-sensitive importers on the critical path of a
read-only feature.

**Recommendation: Z1**, with Z3's migration as a later ticket once the viewers ship.

## Per format family

### Word-processing: DOCX (and DOCM), ODT, RTF

Where each format is parsed, all in Go:

| Format | Package | Reader |
| ------ | ------- | ------ |
| DOCX, DOCM | `pkg/util/docreadutil` | `word/document.xml` through `officezip`, decoded as a token stream. `styles.xml` and `numbering.xml` are read first and held, because a paragraph names its style and list by id. Each is bounded (below). A DOCM is a DOCX with `vbaProject.bin` attached; that part is never opened. |
| ODT | `pkg/util/docreadutil` | `content.xml` (automatic styles at its head, then the body) and `styles.xml`, through `officezip`. |
| RTF | `pkg/util/docreadutil` | a streaming tokenizer of our own over a `bufio.Reader` on the `vfs.File`: control words, groups, `\uN` escapes and code pages. RTF is a flat token stream, so it needs no random access. |

No Go dependency is proposed. The surveyed Go DOCX libraries are writers, or load the whole document into a DOM.
None reads ODT. The RTF libraries found only strip text. The readers needed here are a few hundred lines each on
top of `encoding/xml`.

**Render.** Through `QuarkDocumentView` (Decision 2), at `/document/<path>`:

- Headings come from outline levels: `Heading1`–`Heading6` and `w:outlineLvl` in DOCX, `text:h` in ODT, and
  `\outlinelevel` in RTF.
- Lists come from `numbering.xml`, ODT `text:list` and RTF `\pntext` / `\listtext`.
- Tables carry `gridSpan` / `vMerge` and `table:number-columns-spanned`.
- Tracked changes are shown as accepted: insertions kept, deletions dropped.
- Footnotes and endnotes go at the end, under a "Notes" heading.
- Headers, footers and comments are left out in v1, with a warning.

**Images.** An image block names its part. `GET /previews/part` (see API) streams that part. The app's
`imageBuilder` fetches it and decodes PNG, JPEG, GIF and WebP. EMF and WMF, which Word uses for pasted vector
art, have no decoder in Flutter or in Go's standard library, so they draw a placeholder carrying the alt text.
RTF pictures are inline hex (`\pict`), and v1 shows them as placeholders rather than adding a second way to
address an image.

**Open as Quark doc.** `POST /files/convert/document` runs the same reader through the Delta writer. It writes
`<name>.qdoc` beside the source, conflicting on an existing file unless `overwrite` is set, as
`ConvertXlsxToQsheet` does. It publishes `upload` and returns the import's warnings.

### Markdown

Shipped (Decision 0), at `/markdown/<path>`. The remaining work for #2987 is the two small gaps (ticket 19) and a
word count in the properties sheet (ticket 18), which the client computes from the text it already holds.

### Presentations: PPTX (and PPTM), ODP

**PPTX: parsed in Go, by `pptxutil` as it is.** `GET /previews/slides` calls `pptxutil.ImportPptx` with `Out` set
to the response writer, so the `.qslide` JSON streams slide by slide. Its `StoreMedia` is a view-mode function. It
reads nothing and stores nothing; it returns the reference `part:<zip entry name>` (for example
`part:ppt/media/image3.png`) and discards the reader. This assumes `ImportPptx` lets `StoreMedia` return without
reading the reader to its end. If it does not, the reader is drained into `io.Discard`, which streams the picture
past the server without holding it. Ticket 10 checks which. A PPTM is opened the same way, and
`vbaProject.bin` is never read. `.ppt`, the legacy binary format, has no reader. It leaves the slideshow viewer's
extension set and stays on the generic viewer. A legacy binary `.ppt` reader is out of scope.

**Render.** `/presentation/<path>` shows a thin page around `SlideCanvas.readOnly`: previous and next, a slide
counter, a thumbnail strip on a wide window, and the speaker notes behind a toggle. Its two app-bar actions
reuse existing flows:

- **Present** hands the converted deck to the existing presenter, which needs `SlidePresentController` to accept
  a loaded deck as well as a path.
- **Open as Quark slides** calls the existing `POST /files/import/pptx`.

The import's warnings ("SmartArt not shown") appear in a dismissible notice. This closes #196.

**How a `part:` reference reaches the canvas** needs one decision:

- **I1 (recommended):** add a third `ImageSource` variant, `PackagePartImage`, in `quark_slides`, parsed from the
  `part:` prefix. The app's image builder maps it to `/previews/part`. It is typed, and the editor can refuse to
  save a deck that still holds one.
- **I2:** no package change. `part:...` parses as a `QuarkFileImage` whose path the app's builder
  special-cases. Less code, but the reference is a plain path string, and the editor would try to load it as a
  file.

**ODP: parsed in Go, by a new `pkg/util/odputil`** that writes the same `.qslide` JSON through `officezip`:

- `draw:page` maps to a slide.
- `draw:frame` with `draw:text-box` or `draw:image`, `draw:custom-shape` for the shapes `quark_slides` has,
  `table:table`, and `presentation:notes`.
- What has no model is skipped with a warning, as in `pptxutil`.

This is the largest single reader in the plan, so it comes after the PPTX viewer has shipped. ODP's own import
action follows it, as the same `ImportPptx`-shaped service.

### Spreadsheets: ODS, legacy XLS (and the existing XLSX)

**Parsed in Go, into the `.qsheet` envelope**, the trade `xlsxutil` already makes: one format the sheet UI
understands, and every reader converts into it.

- **ODS:** a new `pkg/util/odsutil` over `officezip`. `content.xml` is streamed. Cell values come from
  `office:value-type` and `office:value` / `office:date-value` / `office:boolean-value`, falling back to the
  `text:p` text. Formulas (`table:formula`) are kept only as their cached value in the view. The repeat
  attributes are the ODS bomb: `table:number-rows-repeated` and `table:number-columns-repeated` let one element
  declare a million rows. Every expansion is counted against `xlsxutil.MaxRows`, `MaxColumns` and `MaxCells`
  before it is materialized. Trailing empty repeats, which LibreOffice writes to the sheet's edge, are dropped
  without being expanded.
- **XLS:** Decision 4.

**Render.** `/workbook/<path>` for `.xlsx`, `.xlsm`, `.ods` and `.xls`:

- `GET /previews/sheet` streams the `.qsheet` JSON from whichever reader matches.
- The page draws it with `data_table`'s `DataSheet` in a new read-only mode: no cell editing, no formula bar
  input, selection and copy kept. This is a small change in `packages/data_table`, which has no read-only flag
  today.
- **Open as Quark sheet** runs the existing conversion, extended to the new readers. `ConvertXlsxToQsheet`
  chooses a reader by extension, and `POST /files/convert/xlsx` accepts `.ods` and `.xls`. The route keeps its
  name, so no client contract breaks. A rename is not worth an API change.
- **Changed behavior:** tapping an `.xlsx` opens this viewer instead of the "convert to `.qsheet`?" prompt. The
  prompt's action moves to the viewer's app bar. This is an open question below.

### Page and word counts, document properties

`GET /previews/properties` reads only the metadata parts and returns `{title, author, subject, created, modified,
pages, words, characters, slides, sheets, application, countsSource}`. It never parses the body, so it stays cheap
enough for the generic viewer:

| Format | Metadata source |
| ------ | --------------- |
| OOXML (DOCX, PPTX, XLSX) | `docProps/core.xml` and `docProps/app.xml` |
| ODF (ODT, ODP, ODS) | `meta.xml`, including `meta:document-statistic` |
| RTF | the `\info` group: `\nofpages`, `\nofwords`, `\creatim`, `\revtim` |

`countsSource` is `"saved"`. The counts are what the authoring application last stored, and the UI says "as
last saved in <application>". Pages can only come from there: paginating a document needs a layout engine Quark
does not have.

The viewer's own `end` line carries counted words, characters and paragraphs, which are exact for what was
parsed. When the viewer is open, its properties sheet prefers them.

**The "file info panel".** Files has none today (see above), so the properties appear in two places:

- an **Info** action (`QuarkBarIconButton`, `info_outline`, "Properties") in each viewer's app bar, opening a
  sheet;
- the details list on `GenericFileViewerPage`, for office files opened there.

A Files-wide info panel would be a separate feature, and is not proposed.

## Memory and streaming

Every limit is checked against bytes actually read, never against a size the file declares. Values are starting
points to tune in the tickets.

| Where | Bound |
| ----- | ----- |
| zip directory | entries ≤ 20,000, checked before the directory is read (the same value as `pptxutil.MaxImportEntries`) |
| one XML part | ≤ 64 MiB decompressed, ≤ 2,000,000 elements, depth ≤ 256 |
| DOCX `styles.xml` and `numbering.xml`, ODF automatic styles | held whole, as the shared string table is in `xlsxutil`; each ≤ 8 MiB decompressed and ≤ 20,000 definitions |
| document blocks | ≤ 50,000 blocks or 16 MiB of NDJSON, whichever comes first, then `truncated: true` |
| RTF | group depth ≤ 256; `\binN` and `\pict` data skipped by streaming discard, never buffered |
| `/previews/part` | streamed with `c.DataFromReader` from the capped part reader; ≤ 100 MiB, the same as `pptxutil.MaxImageBytes` |
| sheets | `xlsxutil`'s existing limits (64 sheets, 100,000 rows, 1,000,000 cells), shared by the ODS and XLS readers |
| slides | `pptxutil`'s existing import limits |
| time | each conversion runs under a request-scoped deadline (30 s) and holds an `iosemutil.Decode` slot, so a burst of opens queues rather than stacking parsers |

Heap per open document is the held style tables plus one XML token at a time, a few megabytes at worst. On the
client, a document is at most the 16 MiB block cap and lays out only what is on screen. A sheet is what the
existing editor already accepts from a conversion.

No converted output is cached on disk in v1. Reopening a document re-parses it. If that measures slow, a cache
under `<data>/cache/previews`, keyed by serial, path, size, mtime and reader version as thumbnails are, is a
contained follow-up.

## Security

The readers run on files any user with upload rights can write, so they are attack surface. A hostile file
should cost one failed request.

- **Zip bombs and quines.** Entry count is checked against the central directory before it is read. Each part
  reads through `io.LimitReader` at its cap, and reaching the cap is an error, not a truncation. A total
  decompressed budget covers each request. Compression ratio is never trusted. The archive-browsing limits in
  `fileutil` are far larger (10 GiB an entry) and are not reused; office parts get the tight caps above.
- **XML.** Go's `encoding/xml` neither resolves external entities nor expands internal DTD entities, so XXE and
  billion-laughs do not apply. Element count and depth limits bound the rest. Decoders run with `Strict` on, and
  a malformed part fails the document.
- **External resources are never fetched by the server.** A relationship with `TargetMode="External"` is never
  followed: linked images, `attachedTemplate` (remote template injection), and linked OLE objects. ODF
  `xlink:href` to anything outside the package is treated the same way, as are RTF `INCLUDEPICTURE` and
  `INCLUDETEXT` fields. A linked image becomes an `image` block with `external: true`. The client draws it as a
  placeholder with its alt text and never loads it. Hyperlinks become `link` runs, and the client opens only
  `http`, `https` and `mailto` through `url_launcher` after a tap, with the Markdown viewer's link policy.
- **Nothing is executed.**
  - Macros (`vbaProject.bin` in DOCM, PPTM and XLSM; ODF `Basic/` and `Scripts/`) are never opened.
  - Field codes (`DDEAUTO`, `INCLUDETEXT`, everything in `w:instrText`) are not evaluated; only their cached
    result text is shown.
  - Embedded OLE objects, ActiveX controls and `w:altChunk` (embedded HTML or RTF) become `omitted` blocks.
  - Spreadsheet formulas show their cached value and are not recalculated on view. On import they come across
    as `xlsxutil` brings XLSX formulas today.
  - RTF `\object`, `\objdata` and `\*\datastore` groups are skipped.
- **Embedded fonts are ignored.** Font parsers are a classic exploit target, and fonts would only matter for
  fidelity.
- **The part endpoint is not a general zip browser.** `/previews/part` serves only:
  - entries under the format's media folders (`word/media/`, `ppt/media/`, ODF `Pictures/`);
  - after `path.Clean`, with no `..`, and present in the zip's directory;
  - with an image extension from the client-decoded set.

  It checks read access on the document's path, exactly as `download-archive-file` does.
- **Images are decoded on the client**, by the same `Image` codecs as everything else. EMF and WMF are never
  decoded.
- **Legacy XLS:** the CFB sector chains are followed with cycle detection and a sector-count bound. BIFF record
  lengths are bounded (8,224 bytes by the format). SST counts are untrusted and checked against
  `xlsxutil.MaxSharedStrings`. An encrypted workbook (`FILEPASS`) is refused with a clear message.
- **Panics** in any reader are recovered per request and answered as a 400 for the file, which is logged.
- **Fuzzing.** Each reader gets a `go test -fuzz` target with a seed corpus of real files. CI runs it seed-only,
  as #2982 proposes for tags.

## Decision 4: reading legacy `.xls`

`.xls` is BIFF8 records inside a Compound File Binary (CFB, also called OLE2) container. Only the cell values
are needed: the shared string table, `LABELSST`, `NUMBER`, `RK` and `MULRK`, `BOOLERR`, the cached result of a
`FORMULA`, `BOUNDSHEET` for sheet names, `CONTINUE`, and date formats from `FORMAT` and `XF`.

### Option X1: `richardlehane/mscfb` for the container, our own BIFF8 reader (recommended)

- **The dependency:** `mscfb` is Apache-2.0. It was pushed in September 2026, has a fuzz target, and has one
  transitive dependency, `richardlehane/msoleps`. It is used by the `siegfried` format identifier. It takes an
  `io.ReaderAt` and returns each stream as a reader, so the `Workbook` stream is read through without
  buffering.
- **Our code:** a BIFF8 record reader for the records above, writing the `.qsheet` envelope with `xlsxutil`'s
  limits. That is roughly 600–900 lines plus tests and a fuzz target. It lives in `pkg/util/xlsutil`.
- **Cost:** two new modules in `go.mod`.

### Option X2: `extrame/xls`

- **What it is:** Apache-2.0, and it reads BIFF5 and BIFF8 values.
- **Against it:** last pushed in September 2023. It has no `go.mod`, and it brings its own `extrame/ole2`. It
  has an open panic report on `WorkSheet.Row` (#66). It decodes a workbook into its own structures, so its
  memory use must be measured before trusting it on large files. Wrapping it means `recover()`, a size
  pre-check, and accepting its allocation behavior.
- **For it:** the least code of our own.

### Option X3: write the CFB reader too

No dependency. CFB is a FAT-style sector format, about 400 more lines, plus another fuzzed parser of untrusted
input. This is the fallback if `mscfb` is not approved.

`shakinm/xlsReader` was ruled out: it is GPL-3.0.

**Recommendation: X1.** It is the smallest well-maintained piece of third-party code, at the layer that is
hardest to get right.

## API

A new handler package, `internal/server/api/v0/previews` (`package v0_previews`), mounted in `apiRouters`. Its
URL segment is `/previews`. Every route is read-only, checks read access on `filePath`, and takes the usual
`filePath` and `serial`. Logic lives in the `pkg/util` readers and a thin `fileutil` function per route. A new
package rather than more routes in `files/` keeps the parallel tickets from colliding on `files/types.go`.

| Method and path | File | Returns |
| --------------- | ---- | ------- |
| `GET /previews/document` | `preview_document.go` | NDJSON blocks (Decision 2) for `.docx`, `.docm`, `.odt` and `.rtf`. A file that is not what its name says is a 400 |
| `GET /previews/slides` | `preview_slides.go` | `.qslide` JSON for `.pptx`, `.pptm` and later `.odp`, with images as `part:` references, plus an `X-Quark-Import-Warnings` count header |
| `GET /previews/sheet` | `preview_sheet.go` | the `.qsheet` envelope for `.xlsx`, `.xlsm`, `.ods` and `.xls` |
| `GET /previews/part?part=` | `get_part.go` | one image from inside the package, streamed. 404 for anything outside the media folders |
| `GET /previews/properties` | `get_properties.go` | the properties object above |

There are two mutations. Both are in `files/`, next to their siblings, and both publish `upload`:

- `POST /files/convert/document` (`convert_document.go`) writes a `.qdoc`.
- `POST /files/convert/xlsx` gains `.ods` and `.xls`.

Every route carries its swagger. As `AGENTS.md` requires, each API ticket is stacked under the Flutter ticket
that consumes it.

## Flutter surface

- **File kinds.** Each new extension is added by the ticket that ships its viewer, never before, so
  `fileKindForName` never points at a viewer that cannot open the file:
  - `.odt`, `.rtf` and `.docm` map to `FileKind.docx`, label "Document".
  - `.pptm` and `.odp` map to `FileKind.slideshow`.
  - `.ods` and `.xls` map to `FileKind.xlsx`, label "Spreadsheet".

  `storageutil`'s type table is updated to match.
- **Routes**, as `/markdown` and `/model` are: `AppRoutes.documentViewer` (`/document/<path>`),
  `presentationViewer` (`/presentation/<path>`) and `workbookViewer` (`/workbook/<path>`). Each gets an
  `opensInXViewer` helper in `lib/utils/<x>_viewer_files.dart`, a `viewFileRedirect` branch, and a
  `file_browser_page.dart` branch. Each viewer kind leaves `usesGenericFileViewer` as its viewer lands.
- **Pages** are thin, per `AGENTS.md`: a `ChangeNotifier` controller with injectable service calls, a service in
  `lib/services/previews_service.dart`, and package widgets composed in `build`. Each page:
  - uses `AutoRefreshMixin`, with `onRefresh` in the app bar slot;
  - puts its actions in the bar as `QuarkBarIconButton` and `QuarkBarChip`, each with a `ValueKey` and tooltip:
    Open as Quark doc / sheet / slides, Present, Properties, Download;
  - takes all error copy from `Errors.message(error, 'open the document')` and friends;
  - shows the disconnected state when the Quark is unreachable.
- **Package widgets:**
  - `QuarkDocumentView` and its model types in `packages/quark_widgets/lib/src/document_view/`, with key prefix
    `document_block_<index>` and `document_link_<index>`. Images go through an `imageBuilder` slot, as in
    `QuarkMarkdownView`.
  - `QuarkDocumentProperties`, the sheet body, in `lib/src/document_view/`.
  - Each has tests at narrow and wide viewports and a gallery entry.
- **Read-only sheet:** a `readOnly` flag on `DataSheet` in `packages/data_table`.
- **Slides:** `PackagePartImage` in `quark_slides` (I1), and `SlidePresentController` taking an already loaded
  deck.

## Sub-tickets, in landing order

Each ticket lands on its own.

- Claims are disjoint between tickets that can run at the same time. A ticket that edits a file an earlier
  ticket created says so, and lands after it.
- Four lanes share files and run in sequence within the lane:
  - **the API lane** (5, 7, 10, 14, 17) shares `docs/swagger/**` and `previews/types.go`;
  - **the app lane** (8, 11, 15, 18) shares `lib/router.dart`, `lib/pages/file_browser_page.dart`,
    `lib/utils/file_kind.dart`, `lib/utils/files_route_path_utils.dart`, `pkg/util/storageutil/storageutil.go`
    and `test/router_test.dart`;
  - **the widget-gallery lane** (6, 18) shares the `quark_widgets` barrel and gallery registry;
  - **the `docreadutil` lane** (2 to 4) shares that package's `docreadutil.go` interface file.
- Everything else runs in parallel.
- This design PR adds the vocabulary the tickets need to `.vscode/cspell.json`, so they do not all claim it. A
  ticket that still needs a new word claims the file, and lands in sequence for that one line.

1. **Bounded office zip reader.** `pkg/util/officezip`: `Open` with entry limits, capped `Part`, the counting XML
   decoder, OOXML relationships with external targets marked, and the ODF manifest. Includes fuzz targets, and
   heap tests showing that a part declaring 1 GiB and a nesting bomb both fail without allocating.
   **Difficulty: hard (parser of untrusted input, allocation safety).**
   Claims: `pkg/util/officezip/**`.
2. **Document block model and DOCX reader.** `pkg/util/docreadutil`: the block types, the NDJSON writer with the
   `end` line and counts, the Delta writer with its loss warnings, and the DOCX/DOCM reader (styles, numbering,
   tables with spans, tracked changes as accepted, notes, omitted objects, external images). Fuzz and limit
   tests. Depends on 1.
   **Difficulty: hard (format semantics, two writers, security rules).**
   Claims: `pkg/util/docreadutil/**`, except the files 3 and 4 claim.
3. **ODT reader.** `docreadutil/odt.go` and `odt_test.go`, plus `testdata/odt/**`, on the same block model.
   Depends on 2; runs beside 4.
   **Difficulty: standard.**
   Claims: `pkg/util/docreadutil/odt*.go`, `pkg/util/docreadutil/testdata/odt/**`.
4. **RTF reader.** `docreadutil/rtf.go` and `rtf_test.go`, plus `testdata/rtf/**`: the streaming tokenizer, code
   pages and `\uN`, lists, tables (`\trowd` … `\row`), skipped destinations, and a fuzz target. Depends on 2;
   runs beside 3.
   **Difficulty: hard (tokenizer of untrusted input, encodings).**
   Claims: `pkg/util/docreadutil/rtf*.go`, `pkg/util/docreadutil/testdata/rtf/**`.
5. **Previews API: document and part.** Creates `internal/server/api/v0/previews` (interface file, `types.go`,
   `helpers.go`, package doc) with `preview_document.go` and `get_part.go`. It also adds
   `fileutil/preview_document.go` and the `routes.go` mount, with swagger and integration tests (access denied,
   traversal in `part`, a non-media part, a truncated stream). It also adds `POST /files/convert/document`.
   Depends on 2; its reader list grows as 3 and 4 land.
   **Difficulty: standard.**
   Claims: `internal/server/api/v0/previews/**`, `internal/server/routes.go`,
   `internal/server/api/v0/files/convert_document.go`, `internal/server/api/v0/files/types.go`,
   `pkg/util/fileutil/preview_document.go`, `pkg/util/fileutil/document.go`, `docs/swagger/**`.
6. **`QuarkDocumentView` widget set.** Model types parsed from the block JSON above, the view, its parts (run
   spans, list item, table with spans, image slot, omitted marker, truncated banner), and
   `QuarkDocumentProperties`. Tests at narrow and wide sizes, and gallery entries. Needs only the shape in this
   doc, so it can start at once.
   **Difficulty: standard.**
   Claims: `packages/quark_widgets/lib/src/document_view/**`, `packages/quark_widgets/test/document_view/**`,
   `packages/quark_widgets/lib/quark_widgets.dart`,
   `packages/quark_widgets/examples/widget_gallery/lib/registry.dart`,
   `packages/quark_widgets/examples/widget_gallery/lib/docs.g.dart`.
7. **Previews API: properties.** `get_properties.go` and `pkg/util/docpropsutil` (OOXML `docProps`, ODF
   `meta.xml`, RTF `\info`). Lands after 5 in the API lane.
   **Difficulty: standard.**
   Claims: `pkg/util/docpropsutil/**`, `internal/server/api/v0/previews/get_properties.go`,
   `internal/server/api/v0/previews/types.go`, `docs/swagger/**`.
8. **Document viewer page.** `/document/<path>`: route, file kinds `.odt`, `.rtf` and `.docm`, viewer-files
   helper, service, controller, page, image builder through `/previews/part`, Open as Quark doc, and the
   `file_browser_page.dart` and `viewFileRedirect` branches. Includes tests. Stacked on 5; uses 6.
   **Difficulty: standard.**
   Claims: `lib/services/previews_service.dart`, `lib/controllers/document_viewer_controller.dart`,
   `lib/pages/document_viewer_page.dart`, `lib/widgets/document_viewer/**`, `lib/utils/document_viewer_files.dart`,
   `lib/router.dart`, `lib/pages/file_browser_page.dart`, `lib/utils/file_kind.dart`,
   `lib/utils/files_route_path_utils.dart`, `pkg/util/storageutil/storageutil.go`, `test/router_test.dart`,
   `test/**/document_viewer_*`.
9. **`PackagePartImage` in `quark_slides`** (I1), and `SlidePresentController` accepting a loaded deck. Can start
   at once.
   **Difficulty: mechanical.**
   Claims: `packages/quark_slides/lib/src/model/image_source.dart`, `packages/quark_slides/test/model/**`,
   `lib/controllers/slide_present_controller.dart`, `test/controllers/slide_present_controller_test.dart`.
10. **Previews API: slides.** `preview_slides.go` calling `pptxutil.ImportPptx` with the response as `Out` and a
    view-mode `StoreMedia`. It confirms whether `StoreMedia` may return without reading its reader to the end,
    and drains to `io.Discard` if not. It extends `get_part.go` to `ppt/media/`. Lands after 7 in the API lane.
    **Difficulty: standard.**
    Claims: `internal/server/api/v0/previews/preview_slides.go`, `internal/server/api/v0/previews/get_part.go`,
    `internal/server/api/v0/previews/types.go`, `pkg/util/fileutil/preview_slides.go`, `docs/swagger/**`.
11. **Presentation viewer page.** `/presentation/<path>` with `SlideCanvas.readOnly`, slide strip, notes toggle,
    Present, Open as Quark slides, the warnings notice, and file kind `.pptm`. Removes `.ppt` from the
    slideshow viewer's set. Closes #196. Stacked on 10; uses 9. Lands after 8 in the app lane.
    **Difficulty: standard.**
    Claims: `lib/controllers/presentation_viewer_controller.dart`, `lib/pages/presentation_viewer_page.dart`,
    `lib/widgets/presentation_viewer/**`, `lib/utils/presentation_viewer_files.dart`,
    `lib/services/previews_service.dart`, `lib/router.dart`, `lib/pages/file_browser_page.dart`,
    `lib/utils/file_kind.dart`, `lib/utils/files_route_path_utils.dart`, `pkg/util/storageutil/storageutil.go`,
    `test/router_test.dart`, `test/**/presentation_viewer_*`.
12. **ODS reader.** `pkg/util/odsutil` into the `.qsheet` envelope, with the repeat-attribute bound and a fuzz
    target. Depends on 1; runs beside 2 to 11.
    **Difficulty: standard.**
    Claims: `pkg/util/odsutil/**`.
13. **XLS reader** (X1). `pkg/util/xlsutil`: `mscfb` for the container, our BIFF8 record reader, `FILEPASS`
    refusal, and a fuzz target. Runs beside everything above.
    **Difficulty: hard (binary format of untrusted input, a new dependency).**
    Claims: `pkg/util/xlsutil/**`, `go.mod`, `go.sum`.
14. **Previews API: sheet, and conversion of ODS and XLS.** `preview_sheet.go`. `ConvertXlsxToQsheet` chooses a
    reader by extension, and `POST /files/convert/xlsx` accepts `.ods` and `.xls`. Depends on 12 and 13; lands
    after 10 in the API lane.
    **Difficulty: standard.**
    Claims: `internal/server/api/v0/previews/preview_sheet.go`, `internal/server/api/v0/previews/types.go`,
    `internal/server/api/v0/files/convert_xlsx.go`, `pkg/util/fileutil/xlsx.go`,
    `pkg/util/fileutil/preview_sheet.go`, `docs/swagger/**`.
15. **Read-only `DataSheet`, and the workbook viewer page.** The `readOnly` flag in `packages/data_table`, then
    `/workbook/<path>` with Open as Quark sheet, file kinds `.ods` and `.xls`, and the XLSX prompt moved into the
    viewer. Stacked on 14; lands after 11 in the app lane.
    **Difficulty: standard.**
    Claims: `packages/data_table/lib/src/data_sheet/**`, `packages/data_table/test/data_sheet/**`,
    `lib/controllers/workbook_viewer_controller.dart`, `lib/pages/workbook_viewer_page.dart`,
    `lib/widgets/workbook_viewer/**`, `lib/utils/workbook_viewer_files.dart`, `lib/services/previews_service.dart`,
    `lib/router.dart`, `lib/pages/file_browser_page.dart`, `lib/utils/file_kind.dart`,
    `lib/utils/files_route_path_utils.dart`, `pkg/util/storageutil/storageutil.go`, `test/router_test.dart`,
    `test/**/workbook_viewer_*`.
16. **ODP reader.** `pkg/util/odputil`, writing `.qslide` JSON through `officezip`, with warnings for what has no
    model. Depends on 1; runs beside the rest.
    **Difficulty: hard (layout and style semantics across two slide models).**
    Claims: `pkg/util/odputil/**`.
17. **ODP in the API.** `/previews/slides` and `get_part.go` (`Pictures/`) accept `.odp`. Adds an ODP import
    service and route beside `import_pptx.go`. Depends on 16; lands after 14 in the API lane.
    **Difficulty: standard.**
    Claims: `internal/server/api/v0/previews/preview_slides.go`, `internal/server/api/v0/previews/get_part.go`,
    `internal/server/api/v0/files/import_odp.go`, `internal/server/api/v0/files/types.go`,
    `pkg/util/fileutil/odp_import.go`, `pkg/util/fileutil/preview_slides.go`, `docs/swagger/**`.
18. **Properties everywhere, and `.odp` in the app.** The Properties action and sheet in the document,
    presentation and workbook viewers and the Markdown viewer (word count computed client-side), and details
    rows in `GenericFileViewerPage`. Also adds file kind `.odp`. Stacked on 7 and 17; lands last in the app lane.
    **Difficulty: standard.**
    Claims: `lib/pages/*_viewer_page.dart`, `lib/controllers/*_viewer_controller.dart`,
    `lib/pages/generic_file_viewer_page.dart`, `lib/services/previews_service.dart`, `lib/utils/file_kind.dart`,
    `lib/utils/presentation_viewer_files.dart`, `pkg/util/storageutil/storageutil.go`,
    `test/pages/*_viewer_page_test.dart`, `test/pages/generic_file_viewer_page_test.dart` (new).
19. **Markdown gaps.** SVG images through `flutter_svg` in `MarkdownViewerImage`, and GitHub alerts
    (`[!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]`, `[!CAUTION]`) as styled callouts in `QuarkMarkdownView`.
    Can run at any time.
    **Difficulty: standard.**
    Claims: `packages/quark_widgets/lib/src/markdown/**`, `packages/quark_widgets/test/markdown/**`,
    `lib/widgets/markdown_viewer/markdown_viewer_image.dart`, `test/pages/markdown_viewer_page_test.dart`.
20. **Journeys and the docs index.** `JN-*` entries for each viewer in `docs.md`, `slides.md`, `sheets.md` and
    `file-browser.md`. Links this page from `docs/architecture/README.md` and drops its "proposal" status. After
    18.
    **Difficulty: mechanical.**
    Claims: `docs/user-journeys/docs.md`, `docs/user-journeys/slides.md`, `docs/user-journeys/sheets.md`,
    `docs/user-journeys/file-browser.md`, `docs/architecture/README.md`, `docs/architecture/read-only-documents.md`.

Not on the list, on purpose:

- moving `pptxutil` and `xlsxutil` onto `officezip` (Z3);
- indexing DOCX, ODT and RTF text for content search through `docreadutil`, which the issue does not ask for;
- a cache of converted previews;
- legacy binary `.doc` and `.ppt`.

Each is a ticket of its own if wanted.

## Open questions for the owner

- **R3 over R1.** R3 accepts a new package widget set and a Go block model so that tables render. R1 reuses
  `flutter_quill` and flattens tables.
- **Dependencies.** X1 adds `richardlehane/mscfb` and `richardlehane/msoleps` to `go.mod`. The fallback is X3,
  writing the container reader ourselves. No Dart dependency is proposed.
- **Text color.** v1 drops authored text color and highlight so that documents stay readable in the dark theme.
  The alternative is to draw documents on a white page surface in both themes and keep their colors.
- **XLSX tap behavior.** The proposal opens the read-only workbook viewer and moves "convert to `.qsheet`" into
  its app bar. The alternative keeps the prompt on tap and reaches the viewer only by deep link.
- **Images in imported `.qdoc` files.** "Open as Quark doc" leaves images out, because the `.qdoc` editor has no
  image embed. Adding one is an editor feature and would need its own design.
