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
  calendar/
    calendar_bar_bottom.dart    the Calendar page's second bar row: period,
                                Today, and the view switch folding to a menu
    calendar_body.dart          picks the view to show, with the reminder bar,
                                load states, and swipe to step
    calendar_event_editor_host.dart
                                CalendarEventEditor around a
                                CalendarEditorController; confirms delete
    show_calendar_event_editor.dart
                                opens that form as a sheet or a dialog
  chat/
    chat_unlock_prompt.dart     the password prompt in place of chat while it
                                is locked (web after a reload)
    chat_failed_send_bar.dart   Retry and Discard for a message that didn't
                                send; the package list has no failed row
    chat_channel_header.dart    the open channel's name and topic, and its
                                settings menu
    chat_channel_not_found.dart a link to a channel the account can't open,
                                in place of the messages; reads Errors
  file_browser/
    file_browser_view.dart      lists files, calls FilesService
    file_top_bar.dart           Files' QuarkAppBar: holds the inline search
                                state and takes the app's StorageDevice
    file_top_bar/               its parts, on the package bar buttons
    file_storage_footer.dart    capacity row, takes the app's HealthStatus
    files_welcome_card.dart     WelcomeCard wired to AppSettings: the greeting
                                on the Files landing after setup or sign-in
    folder_explainer.dart       WelcomeCard saying what users, groups and
                                groups/everyone are for; reads the path utils
    recent_files_section.dart   calls FilesService
    new_file_dialog.dart        one-line wrapper that pops NewFileDialog
    upload_conflict_prompt.dart pops UploadConflictDialog and holds the
                                "do the same for the rest" tick while it is open
  jobs/
    job_finish_announcer.dart   shows a snack bar for every job JobsController
                                announces finished, and navigates its action
  layout/
    app_bar_trailing_host.dart  provides the QuarkAppBarTrailing scope with a
                                ConnectionIndicator fed by ConnectionController
                                and a JobsBadge fed by JobsController
    app_drawer.dart             AppDrawer, QuarkDrawer wired to the router
    chrome_app_bar.dart         ChromeAppBar, a drill-down page's AppBar under
                                QuarkChrome; not coupled, a candidate for the
                                package
    theme_toggle_button.dart    AppThemeToggle, ThemeToggleButton wired to AppSettings
  login/
    active_host_card.dart       the active Quark from AppSettings, with the
                                button that expands the host list
    host_switcher.dart          ActiveHostCard plus the inline HostManager,
                                shared by the login and setup pages
  photos/
    add_to_album_sheet.dart     AddToAlbumSheet host for a photo in an album
                                view: calls AlbumService, shows snack bars
  settings/
    repair_installation_section.dart
                                hosts RepairController: the repair button and
                                its confirmation, or the one-time install step
    sessions_section.dart       hosts SessionsController: the account's sessions,
                                signing one out or all the others, each
                                behind a confirmation
    ssh_access_section.dart     hosts SshAccessPanel around SshAccessController,
                                with its confirmation, key and password dialogs
  sharing/
    show_share_sheet.dart       opens ShareSheet around a ShareController for
                                a ShareTarget, a file or folder or a chat
                                channel's members; confirms owner changes
                                and, for a channel, key-rotating ones
  slides/
    chart/                      charts (#1160): the kind picker with live
                                previews, the Edit data dialog (reads the
                                clipboard, writes errors with Errors, applies
                                through SlideEditorController), the series
                                colors menu, the title field and the
                                properties section
    import/                     importing a PowerPoint file: the Slides
                                bar's Import row, the progress and summary
                                dialogs, and importPowerPointAndOpen, which
                                writes errors with Errors and opens the new
                                presentation through the router
    insert/                     picking a picture for a slide, or a
                                PowerPoint file to import: the Quark folder
                                browser (lists through an injected function)
                                and the upload progress strip
    properties/                 the properties panel and its fields: reads
                                SlideEditorController and calls its commands
    theme/                      the theme and layout pickers (#1163):
                                SlideThemePicker and SlideLayoutPicker are
                                data in, callbacks out; SlideThemeControl,
                                SlideLayoutControl and SlidePickerMenuButton
                                read SlideEditorController and call its
                                commands
    transition/                 the transition picker (#1164): its kind,
                                direction and length fields, the preview
                                stage and the thumbnail marker are data in,
                                callbacks out; SlideTransitionControl and
                                SlideTransitionMenuButton read
                                SlideEditorController and call its commands
    toolbar/                    the slide toolbar: SlideToolbarActions maps
                                the controller into choices, the rows and
                                phone menus draw them; SlideToolbarGroup is
                                the registry of formatting groups
    shortcuts/                  the keyboard shortcuts dialog (searchable, key
                                caps per platform) from lib/utils/
                                slide_shortcuts.dart, and SlideShortcutsHelp,
                                which opens it on ? and F1
    slide_editor_body.dart      the slide editor under its bar: reads
                                SlideEditorController and calls its commands
    slide_editor_bar_bottom.dart
                                the editor's zoom row, from the controller
    slide_editor_canvas.dart    the package's SlideCanvas bound to the
                                controller's document, selection and zoom
    slide_editor_shortcuts.dart the editor's undo and redo keys
    slide_image.dart            a slide picture from the authenticated
                                download URL, with loading and error states
    slide_save_status.dart      the editor's save chip, from SlideSaveState
    slides_body.dart            the Slides list: its rows open editors through
                                ContentResultTile's router call
    slides_error_view.dart      opens Settings from the disconnected view and
                                writes its sentence with Errors
    slide_panel.dart            the slide panel, slide_thumbnail.dart its rows
    slide_thumbnail.dart        drawn by a read-only SlideCanvas: data in,
                                callbacks out, app-side while it sizes itself
                                to the editor's split and takes the app's
                                image builder
    slides_search_bar.dart      the list's filter field
  system/
    health_tab.dart             the System page's tabs: each loads and
    storage_tab.dart            refreshes itself through its service or
    jobs_tab.dart               JobsController, and reports whether it is
                                refreshing to the page's app bar
  thumbnails/
    backfilling_thumbnail.dart  builds a Quark thumbnail and, when it fails,
                                asks ThumbnailBackfill to render and upload one
  users/
    user_avatar.dart            UserAvatar, a QuarkAvatar showing an account's
                                picture from UsersService.avatarUrl
  video_viewer/
    convert_video.dart          runs TranscodeDialogHost, queues the job and
                                shows its snack bar; the viewer and Files share it
    transcode_dialog_host.dart  hosts TranscodeDialog around an injected
                                formats loader
  content_result_tile.dart      one docs/sheets/slides content search hit; pushes the
                                editor its extension names
  doc_sheet_tile.dart           one doc, sheet or slides row, shared by filename and
                                content matches so they look alike (#2272)
  host_dialog.dart              edits AppSettings hosts
  host_manager.dart             edits AppSettings hosts
  nearby_quarks.dart            hosts DiscoveredQuarkList around a
                                QuarkDiscoveryController browsing mDNS
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
`photos_empty_state.dart`,
the album dialogs and menu (`album_name_dialog.dart`,
`delete_album_dialog.dart`, `album_actions_menu.dart`), the menu and
confirmation for a photo in an album view (`album_item_menu.dart`,
`remove_from_album_dialog.dart`), the menu for a photo in the library
(`library_photo_menu.dart`), and
`album_picker_sheet.dart`, which hosts the package `AlbumPickerSheet` around an
injected loader. `device_upload_picker.dart` likewise only holds the choice for
the package `UploadTargetPicker`. Selecting wears the package
`FileSelectionBar`, the same bar Files and the trash use.

Settings is split into tabs (#2350), one widget each under `settings/`:
`settings_general_tab.dart`, `settings_account_tab.dart`,
`settings_network_tab.dart`, `settings_updates_tab.dart`,
`settings_about_tab.dart` and the admin-only `settings_features_tab.dart`
(#2542), which lists the package `FeatureFlagTile` over the app's
`FeatureFlag` model, with the Network tab's `remote_access_card.dart` and
`connected_devices_card.dart`. The page still loads everything and hands each
tab its values and callbacks; the tabs stay app-side because they take the
app's service models and host `HostManager`, `SessionsSection`,
`SshAccessSection` and
`RepairInstallationSection`.

## Adding a widget

If it is presentational — data in, callbacks out, no services and no
navigation — it belongs in `packages/quark_widgets`, not here. Follow the
"Adding a widget" steps in that package's README, and the **Widget package
rules** section of [`AGENTS.md`](../../AGENTS.md) for the contract.

If it genuinely needs a service, put it here and keep it thin: a package widget
for the visuals, wrapped by an app widget that supplies the data and handles
the callbacks. `layout/theme_toggle_button.dart` is the smallest example of
that shape.
