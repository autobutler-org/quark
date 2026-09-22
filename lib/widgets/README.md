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
    file_storage_footer.dart    capacity row, takes the app's HealthStatus
    recent_files_section.dart   calls FilesService
    new_file_dialog.dart        one-line wrapper that pops NewFileDialog
    upload_conflict_prompt.dart pops UploadConflictDialog and holds the
                                "do the same for the rest" tick while it is open
  jobs/
    job_finish_announcer.dart   shows a snack bar for every job JobsController
                                announces finished, and navigates its action
    jobs_badge_host.dart        provides the QuarkAppBarTrailing scope with a
                                JobsBadge fed by JobsController
  layout/
    app_drawer.dart             AppDrawer, QuarkDrawer wired to the router
    theme_toggle_button.dart    AppThemeToggle, ThemeToggleButton wired to AppSettings
  photos/
    add_to_album_sheet.dart     AddToAlbumSheet host for a photo in an album
                                view: calls AlbumService, shows snack bars
  settings/
    repair_installation_section.dart
                                hosts RepairController: the repair button and
                                its confirmation, or the one-time install step
    ssh_access_section.dart     hosts SshAccessPanel around SshAccessController,
                                with its confirmation, key and password dialogs
  sharing/
    show_share_sheet.dart       opens ShareSheet around a ShareController for
                                one file or folder; confirms owner changes
  video_viewer/
    transcode_dialog_host.dart  hosts TranscodeDialog around an injected
                                formats loader
  content_result_tile.dart      one docs/sheets content search hit; pushes the
                                editor its extension names
  doc_sheet_tile.dart           one doc or sheet row, shared by filename and
                                content matches so they look alike (#2272)
  host_dialog.dart              edits AppSettings hosts
  host_manager.dart             edits AppSettings hosts
  quark_connect_form.dart       calls the connection services
  search_section_header.dart    labels a group of docs/sheets search results,
                                shared by both pages' bodies
  text_controller_scope.dart    owns a dialog's TextEditingController, so it is
                                disposed with the dialog rather than when the
                                dialog's future completes (#2012)
  upload_drop_zone.dart         takes a desktop drop through desktop_drop, an
                                app dependency the package does not have
```

The photos page is decoupled (#1732): `PhotosController` makes its service
calls, and what is left under `photos/` is the page's own parts. They hold no
domain state and call no service, but they are app-side because they need
something the package does not have or are only ever used by that page:
`photo_thumbnail.dart` (photo_manager and `Image.network`),
`photos_selection_app_bar.dart` (`AppThemeToggle`), `photos_empty_state.dart`,
the album dialogs and menu (`album_name_dialog.dart`,
`delete_album_dialog.dart`, `album_actions_sheet.dart`), the menu and
confirmation for a photo in an album view (`album_item_menu.dart`,
`remove_from_album_dialog.dart`), and
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
