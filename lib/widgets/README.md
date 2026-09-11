# Quark app widgets

Everything reusable and presentational now lives in
[`packages/quark_widgets`](../../packages/quark_widgets/README.md), imported
through the single barrel `package:quark_widgets/quark_widgets.dart`. That
package's README is where you go to read a widget's API, and its
`examples/widget_gallery` renders every one of them with fake data over a theme
you can edit while it runs.

What is left here is the widgets that are still coupled to the app: they call
services, push routes, show snack bars, or read `AppSettings`. Each is waiting
on its page's decoupling issue (see #1600), after which it moves too.

```text
lib/widgets/
  file_browser/
    file_browser_view.dart      lists files, calls FilesService
    file_top_bar.dart           search and sort chrome, calls FilesService
    file_storage_footer.dart    capacity row, calls StorageService
    recent_files_section.dart   calls FilesService
    new_file_dialog.dart        one-line wrapper that pops NewFileDialog
  layout/
    theme_toggle_button.dart    AppThemeToggle, ThemeToggleButton wired to AppSettings
  photos/
    add_to_album_sheet.dart     AddToAlbumSheet host for the album page: calls
                                AlbumService, shows snack bars
  host_dialog.dart              edits AppSettings hosts
  host_manager.dart             edits AppSettings hosts
  quark_connect_form.dart       calls the connection services
```

The photos page is decoupled (#1732): `PhotosController` makes its service
calls, and what is left under `photos/` is the page's own parts. They hold no
domain state and call no service, but they are app-side because they need
something the package does not have or are only ever used by that page:
`photo_thumbnail.dart` (photo_manager and `Image.network`),
`photos_selection_app_bar.dart` (`AppThemeToggle`), `photos_empty_state.dart`,
the album dialogs and menu (`album_name_dialog.dart`,
`delete_album_dialog.dart`, `album_actions_sheet.dart`), and
`album_picker_sheet.dart`, which hosts the package `AlbumPickerSheet` around an
injected loader. `device_upload_picker.dart` likewise only holds the choice for
the package `UploadTargetPicker`.

## Adding a widget

If it is presentational — data in, callbacks out, no services and no
navigation — it belongs in `packages/quark_widgets`, not here. Follow the
"Adding a widget" steps in that package's README, and the **Widget package
rules** section of [`AGENTS.md`](../../AGENTS.md) for the contract.

If it genuinely needs a service, put it here and keep it thin: a package widget
for the visuals, wrapped by an app widget that supplies the data and handles
the callbacks. `layout/theme_toggle_button.dart` is the smallest example of
that shape.
