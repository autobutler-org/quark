# Backend cleanup

Working notes from a read of the Go backend on 2026-10-21. This is a hand-refactor guide, not a design to implement as one change. API shape stays as it is. WebDAV is a spike, tracked at the end, and is not part of the cleanup.

The route map is 194 routes, each with a swagger entry, and every handler package under `internal/server/api/v0/` is mounted.

A cleanup can remove a few thousand lines of unreachable helpers and repeated handler boilerplate. It will not shrink the backend in a meaningful way. The bulk is auth, the file API, photos, storage, and the document parsers the app already opens.

## Counts

`gmake cloc` counts git-tracked files, skips Markdown, and skips generated Go (`internal/db/*.sql.go`, `internal/db/querier_postgres.go`, `docs/swagger/`, `internal/server/public/`, `*.g.dart`). Its code column drops blank lines and comments. A fresh run of those flags matches `cloc-report.before.md` for Go: 1,086 files, 16,177 blank, 25,044 comment, 162,802 code. The report's total is 448,069. The fresh run's total is 448,071. The two extra lines are JSON. Go did not move.

That 162,802 is every non-generated Go file in the repo, tests included. It splits as:

| Slice | Code | Blank | Comment | Physical |
| --- | ---: | ---: | ---: | ---: |
| Backend production (`cmd`, `internal`, `pkg`, no `_test.go`) | 65,399 | 7,563 | 18,165 | 91,127 |
| Backend tests | 81,470 | 8,495 | 6,751 | 96,716 |
| Backend total | 146,869 | 16,058 | 24,916 | 187,843 |
| Go under `test/` and `docs/` | 15,933 | 119 | 128 | 16,180 |
| Repo Go, the report's Go row | 162,802 | 16,177 | 25,044 | 204,023 |

Physical is code plus comment plus blank, which is what `wc -l` reports. The package figures below are physical lines, and each one equals that package's cloc code, comment, and blank added together. Where a cut is sized in cloc code as well, both numbers are given.

Comment share in the comment pass is cloc comment divided by comment plus code, on production files only. `pkg/util` is 11,543 / 56,088 (20.6%). `internal/server` is 4,010 / 16,060 (25.0%). Both match the report's definitions.

Do the work in the order at the bottom.

## The decision that dominates the line count

Three packages have no production caller. Only their own tests import them.

| Package | Prod code | Prod physical | Test code | Test physical | What it is |
| --- | ---: | ---: | ---: | ---: | --- |
| `pkg/util/odputil` | 2,361 | 2,902 | 709 | 772 | `.odp` to `.qslide` |
| `pkg/util/odsutil` | 1,269 | 1,527 | 550 | 608 | `.ods` to `.qsheet` |
| `pkg/util/xlsutil` | 1,003 | 1,365 | 708 | 874 | legacy `.xls` to `.qsheet`, plus the `mscfb` dependency |

`docs/architecture/read-only-documents.md` still lists wiring them as later steps: ODS, XLS, then ODP, then `/previews/sheet` and `/previews/slides`. `fileutil` still refuses `.xls` on purpose. Nothing in `internal/server` calls them. This is library code from that design that never grew a route.

If those viewers are still the plan, leave the packages and wire them as their own stack later. Rewriting them now wastes the work. If the plan is stalled and the tree should match what the product does today, deleting the three packages is 6,600 lines of cloc code (8,048 physical) and one dependency. That is a product call, separate from the cleanup.

## Pass 1: delete confirmed-dead code

These have no caller outside their own tests. `BytesToKB` and `BytesToMB` stay. `internal/server/server.go` logs with `BytesToMB`.

- `pkg/util/fileutil/document.go` `IsDocumentPath`. Zero callers, including tests. Convert already uses `docreadutil.FormatForName`.
- `pkg/util/authutil/authutil.go` `IsActive` and `IsActiveAs`. The comment on `IsActiveAs` says the event stream calls it. The stream does the check itself in `internal/server/api/v0/events/helpers.go`.
- `pkg/util/photoutil/photoutil.go` `FilterPhotoFiles`. Listings use `DetermineFileTypeFromPath`.
- `pkg/util/storageutil`: `VideoMIMETypeFromExtension`, `SizeBytesToString`, `GetDeviceInfoForPath`, `GetAvailableSpaceInBytes`, `Summary` / `CalculateSummary`, `ClassifyDiskSpeed`, and the byte helpers that only those call (`BytesToGB`, `BytesToTB`, and the inverse converters). Keep `BytesToKB` and `BytesToMB`.
- `pkg/util/settingsutil` `GetActiveBranch` and `SetActiveBranch`. Keep the `ActiveBranch` field so a stored value still round-trips.
- `pkg/util/chatutil` `ResolveMemberUsers`. Production calls unexported `memberUsers`.
- `pkg/util/iosemutil` `(*Semaphore).Available`. The comment says it is for monitoring. Nothing logs it.
- `pkg/util/serverutil` `NewHttpErrorf` and `RegisterRouter`. Production uses `NewHttpError` and `RegisterRouterWithGroup`.
- `pkg/backup/sync.go` `QueueLength`.
- `sql/queries/content_search.sql` `GetFileContent`, then regenerate sqlc. The upsert and delete queries are live.

That cluster is roughly 500 to 700 lines, plus the tests that exist only to call them.

While you are in `storageutil`, `DetermineFileTypeFromPath` calls `os.Stat` for an extension it does not recognize. Callers pass VFS-relative names (`fileutil/list.go`, `photoutil`). That stat hits the process working directory. The directory bit already comes from `VFS.Stat`.

`DBVFS` / `NewDBVFS` is gone. The server never constructed it. `vfs_db_entries` stays; dropping the table is a later migration. Leave migration `007` alone.

## Pass 2: collapse copies into functions

The package count is not the problem. There are about 64 `pkg/util` packages and 30 API packages because each one is a domain the handler layer is required to call. `ctxutil`, `sqlutil`, `bookutil`, `githubutil`, `playbackutil`, and the other small ones are either widely imported or the service behind one route. Folding them into neighbors fights `scripts/check-go-structure.bash` and saves tens of lines. Leave them.

What is worth a function:

1. The files access preamble. Pull deps, `accessutil.LoadRequest`, then map "not readable" to 404 and "not allowed" to 403. Inlined in `list_files.go`, `stat_file.go`, `delete_files.go`, `move_file.go`, `new_folder.go`, `convert_document.go`, `convert_xlsx.go`, `export_pptx.go`, `export_xlsx.go`, and `import_pptx.go`. Chat, versions, and music already have this helper. Put it in `internal/server/api/v0/files/helpers.go`. About 200 lines if you stop at the files package. Eight handlers still return `fmt.Errorf("dependencies not found in context")` instead of `InternalServerError(nil)`: `auth/delete_account.go`, `auth/list_sessions.go`, `auth/revoke_session.go`, `auth/revoke_all_sessions.go`, `photos/pause_index.go`, `photos/resume_index.go`, `photos/get_index_status.go`, and `photos/list_duplicates.go`. Keep their status codes.
2. `grantOwner`, copied in `files/helpers.go`, `photos/helpers.go`, and `videos/helpers.go`. The 404 text stays per type (`"file not found"`, `"photo not found"`, `"video not found"`).
3. `export_pptx.go` and `export_xlsx.go` are the same streaming handler with the media type and the service call swapped. `convert_document.go` and `convert_xlsx.go` share the same parent-directory gate. One helper each. The office parsers stay where they are. `ConvertDocumentToQdoc` (`fileutil/document.go`) and `ConvertXlsxToQsheet` (`fileutil/xlsx.go`) share the sibling-path, clobber check, open, and temp write. Pptx import is a different shape (a media directory, and no overwrite).
4. Four namespace lookups: `fileutil.FilesVFS`, `photoutil.DeviceFS`, `uploadutil.Destination.FilesVFS`, `videos/helpers.go` `filesVFS`, and `trashutil` `trasherFor`. They disagree on what a missing serial returns (`ErrNoFilesNamespace`, `vfs.ErrNotFound`, nil, `ErrDeviceNotFound`). Point them at `FilesVFS` and map the error at the edge. The nil-versus-typed-error difference is the bug this split can hide.
5. `StorageServiceVFS.filesDir` and `attached` both call `FindManagedDeviceBySerial`. `MkdirAll` and `Move` call both, so one mkdir looks the device up twice. `pkg/vfs/storageservice_vfs.go`.
6. Auth's wrong-password mapping is inlined three times: `change_password.go`, `set_recovery_key.go`, and `delete_account.go`. `ErrIncorrectPassword` becomes 403, `ErrUserNotFound` becomes 401. `accountRefusalResponse` already covers pending and disabled.

`writeJSONRow` / `writeJSONString` are copied in `xlsxutil/qsheet.go`, `xlsutil/qsheet.go`, and `odsutil/qsheet.go`. The Excel date-serial helpers are copied in `xlsxutil/styles.go` and `xlsutil/format.go`. That merge only pays if you keep the readers that have no route.

The live zip duplication is `pptxutil/import_archive.go` (299 lines) and `xlsxutil/part.go` plus the rels helpers in `xlsxutil/workbook.go`. `officezip` already does this for `docreadutil`, `odsutil`, `odputil`, and `docpropsutil`. The same bodies show up as:

- `zipDirectory` in `pkg/util/officezip/helpers.go` and `pkg/util/pptxutil/import_archive.go`
- `safePartName` and `resolveTarget` in those same files. A weaker third `resolveTarget`, which does not reject `..`, is in `xlsxutil/workbook.go`
- `budgetReader.Read` and the XML token cap, again `officezip/helpers.go` and `pptxutil/import_archive.go`

`docs/architecture/read-only-documents.md` deferred moving PPTX and XLSX onto `officezip`. The limits differ. PPTX allows a 2 GiB package and 32 MiB XML parts. `officezip` defaults are much tighter and would start rejecting workbooks that convert today. Pass the existing limits through. Do this as its own change, after the dead-code pass. Keep the PresentationML decode in `import_xml.go`.

Do not merge the parsers. BIFF8, OOXML, and ODF share a `.qsheet` grid and a JSON row writer. The readers are a record stream, worksheet XML, and `content.xml`. PresentationML and ODP both emit `.qslide` and otherwise differ, including the `StoreMediaFunc` signature. `docpropsutil` stays out of `docreadutil` because properties must not parse the body. `bookutil` and `audiotagutil` are different features.

## Pass 3: comments

About 20% of `pkg/util` lines are comments, and about 25% of `internal/server`. Most of that has to stay. Swagger godoc is how CI stays in sync with the 194 routes. Package comments are what revive checks. The `ponytail:` notes and the limit comments (zip bombs, session renewal, symlink escape) are the constraint. Deleting them makes the next edit guess.

Delete the comments that restate the next line, in the same commit as the dead function when they sit on one:

- `xlsxutil/qsheet.go` on `writeJSONRow`, `worksheet.go` on `blankRow` and `attrString`, `export.go` on `truncateRunes`.
- `photoutil.go` on `FilterPhotoFiles`, `storageutil/summary.go` on `CalculateSummary`, `storageutil.go` on `GetDeviceInfoForPath` and the "could be enhanced later" paragraph under it.
- `pkg/vfs/local.go` on `List`, `Open`, `Write`, and `MkdirAll`. Keep the sentence about the temp-file rename.
- `NewRouter returns the videos API router` in the API interface files. The package comment already names the URL. Same line in albums, photos, and books.
- `fileutil/document.go` `openXlsx`. The name is wrong. PPTX import uses it too. Rename the function and the comment goes.
- `storageutil/detector_darwin.go` section banner `Helper functions`.
- `photoutil/raw_convert.go` "Returns the decoded image…". Keep the timeout comment above it.
- `tlsutil.go` "Returns the paths to the cert and key files." Keep the regen rules above it.
- `settingsutil.go` comments on `GetDeviceID`, `GetActiveBranch`, and `SetActiveBranch`, when those functions go.
- `iosemutil` comment on `Available`, when the method goes.
- `authutil.go` comment on `IsActiveAs`. The sentence is stale. The stream's check is `events/helpers.go`.

Keep these:

- `internal/server/middleware/middleware.go` `requireAuth` precedence (Bearer, cookie, `?token=`, download token, Basic).
- `internal/server/server.go` on `middleware.Use` running before `setupRoutes`. Gin does not apply middleware registered after routes.
- `authutil.go` `DeleteAccount` wipe order.
- `pkg/vfs/storageservice_vfs.go` `mimeTypeForName` on HEIC, HEIF, TIFF, and BMP. Go's `mime` package returns an empty string for those.

## Pass 4: tests

The tests are not padding. The high ratios are small packages (`ctxutil` is 23 lines of `gin.Context.Set` and `Get`) and handler suites that are the HTTP contract. Cutting the list below is about 1,000 to 1,300 physical lines. Cutting `authutil` (3,681 lines of test code, 4,496 physical, across 25 files) or the files suite (5,018 lines of test code, 6,129 physical, across 28 files) would drop coverage of lockout, last-admin races, path traversal, and zip limits.

Trim only these:

- `pkg/util/ctxutil/ctxutil_test.go`. Keep `TestGet_WrongType`. The rest retests gin.
- `pkg/util/sqlutil/sqlutil_test.go`. Keep nil versus zero, non-UTC normalized to UTC, and SQL NULL versus an empty string. Keep `unique_test.go` whole. That is the SQLite-versus-PostgreSQL `23505` check.
- `pkg/util/versionutil`. Delete `TestGetVersion`, `TestGetVersion_Fields`, and `TestNewVersion`. They log fields or check that a constructor copied its arguments. Collapse `TestCompareVersions_InvalidVersions` to one case. Keep `TestGetVersion_PrefersStampedCommit` and one real compare table.
- `pkg/util/githubutil/githubutil_test.go`. Delete `TestFetchGitHubReleases_Integration` (permanently skipped), `TestFetchGitHubReleases_NonExistentRepo` (live network, same branch as the HTTP-error test), `TestFetchGitHubReleases_ServerError`, and both JSON unmarshal tests.
- `internal/server/api/v0/books/books_test.go`. Delete `TestListBooks_EmptyDir`, `TestListBooks_IgnoresNonBookFiles`, `TestListBooks_PdfIncluded`, `TestListBooks_SubdirectoryRecursion`, and `TestListBooks_SkipsTrash`. `bookutil.TestFindBooks` already walks those paths. Keep `TestListBooks_WithEpub`, `TestListBooks_NoNamespace`, and the access test.
- `internal/server/api/v0/files/stat_file_test.go`. Merge `TestStatFile_QdocFile` through `TestStatFile_FolderNamedLikeVideo` into one table. Keep not-found, and a directory whose name looks like a file.
- `internal/server/api/v0/events/events_test.go`. Delete `TestStreamEvents_ConnectsSuccessfully`, `TestStreamEvents_MultipleEventTypes`, and `TestStreamEvents_ClientDisconnectUnsubscribes`. Keep `TestStreamEvents_ReceivesPublishedEvent` and the access, role, status, and cache integration files.
- `internal/server/api/v0/videos/trim_actual_start_test.go`. Delete `TestTrimReportsTheSparseGOPStart` and `TestTrimNumberedClipsReportTheirOwnStart`. `videoutil` already has those. Keep `TestTrimStopsWhenTheClientGoesAway`.
- `videos/transcode_test.go` `TestTranscodeRunsToCompletion`. The lifecycle test already remuxes the same fixtures.
- `internal/server/api/v0/version/version_test.go` `TestGetInstalledVersion_ReturnsOK` and `TestGetSbom_ReturnsOK`. The next test hits the same 200 and checks the body.
- `internal/server/api/v0/favorites` `TestToggleFavorite_AddsThenRemoves`. Same toggle as `favoritesutil`, with no extra assertion.
- `authutil/wordlist_test.go` `TestPhraseEntropy`. It asserts `16 * log2(256)`. Keep `TestWordlist` and `TestWordlist_Unambiguous`.
- In `videos/transcode_test.go` `TestTranscodeEnqueueFailureIsLoggedAndNamed`, drop the slog substring check. Keep the 500 body.

Leave these, even where they are long:

- Every `access_integration_test.go`, especially `files/access_integration_test.go`, including symlink escape.
- `internal/server/middleware` auth tests, `extension_contract_test.go`, forwarded-for, and access-log redaction.
- `authutil` as a set. Lockout is four layers on purpose: `login_guard_test.go`, `basic_auth_test.go`, the middleware 429, and `auth/login_lockout_test.go` `Retry-After`. Dropping one leaves a seam untested. `auth/legacy_account_test.go` pins 401 versus 426 versus 500. The service test only checks the hash rewrite.
- Archive limits, range requests, zip64, `TestDecodeImage_RefusesPixelsOverTheCap`, and `TestLargeArchiveEntriesStream`.
- `internal/db/migrations_test.go`, `internal/db/schema_recovery_test.go`, and `sqlutil/unique_test.go` `TestIsUniqueConstraintErrOnEachEngine`.
- Files traversal tests: `TestDeleteEscapingPathIsBadRequest`, `TestEscapingPathIsBadRequestOnListAndMove`.

`authutil`'s 25 test files each own a scenario (homes rolled back when the grant fails, sliding expiry, device wipe, one founding admin under concurrent setup). Do not cut that package down to a handful of files. The repeated case is "wrong password or unknown user returns invalid credentials." One wrong-password test on `Login` and one on `AuthenticateBasic` cover it. Keep the status test, because a pending account with the right password must not look like a stranger, and a pending account with the wrong password must.

The files handler tests have no single harness. `newTestEngine` lives in `files_integration_test.go`. `accessHarness` is shared by the home and group-folder tests. Other files build an engine locally. The repeated block is about 30 lines of gin setup, eight times. That is wiring, not duplicated assertions. Merging the constructors does not remove the tests that matter.

## WebDAV is a spike

Class 1 WebDAV (PROPFIND, GET, PUT, DELETE, MKCOL, MOVE, and file COPY) is a new HTTP handler in front of code that already exists. It needs its own mount. Overloading `GET` and `PUT /api/v0/files` would change the REST contract the app already uses.

Call these from that handler:

- `fileutil.FilesVFS`, `accessutil.Canonical`, `accessutil.LoadRequest`, and `Access.Check` for the path jail and the grant check.
- `VFS.Stat`, `List`, `Open` (`io.ReadSeeker` and `ReaderAt`), `Write`, `MkdirAll`, `Move`, and `Copy`.
- `fileutil.MoveFile`, `CreateFolder`, `DeleteFiles`, and `uploadutil.WriteFile` for anything that must publish events and carry access rows and photo rows. A handler that called `VFS.Delete` directly would trash nothing and leave every open client stale. User delete goes through `vfs.Trasher`. `VFS.Delete` is permanent.
- Basic auth already exists, and only on `/api/`. The password it accepts is the account auth key. A login password is 426. A mount outside `/api/` is unauthenticated today. Extending `requireAuth` to a new prefix is part of the spike.

Each of these stays in the spike:

- LOCK and UNLOCK. There is no lock token anywhere. Refusing locks and advertising Class 1 changes nothing in the current API. A lock table is a spike.
- Dead properties. `MetadataStore` (`pkg/vfs/vfs.go`) is arbitrary JSON, and the only production key is `playback.<userID>`. Live DAV properties are `FileInfo`. Putting DAV properties in that map without a reserved prefix can overwrite playback state.
- Collection COPY. File copy exists. Recursive copy exists only inside a cross-device move (`fileutil/move.go`). Build it on the WebDAV mount from `Walk`, `MkdirAll`, and `CopyBetween`. A `POST /files/copy` route is a different change.
- MKCOL's exact failures. `CreateFolder` uses `MkdirAll` and treats "already there" as success. WebDAV must return 409 when a parent is missing and when the collection exists. Check that in the new handler. Changing `CreateFolder` would change REST.
- 207 Multi-Status, the WebDAV `If` header, and partial PUT. `VFS.Write` replaces the whole file. `IfNoneMatch` on write is only `"*"`. Class 1 does not need an in-place range write.
- DELETE permanence. Reusing `DeleteFiles` hides the name and keeps the bytes until purge. A permanent WebDAV delete that skipped trash, access-row moves, and events would leave the app showing files that are already gone.

`sshutil` is not a filesystem protocol. It turns sshd on and writes `authorized_keys`. There is no SFTP, FTP, or WebDAV server in the repo. An SSH shell can read the host files directory and skip VFS, access checks, and events. That is the outcome to avoid.

Do not add interfaces to get ready for WebDAV. `VFS` already has the optional capabilities that earned a second implementation (`HostPather`, `Walker`, `FileMover`, `Trasher`). `Dependencies`, `UsbDevice`, `Detector`, and `Partition` are the same kind of seam. A document-reader interface, or a WebDAV interface with one implementation, is how this tree grew packages. A new format is a package plus a switch on the extension in `fileutil`, which is what XLSX and PPTX already do.

Do not refactor the files handlers so a later WebDAV mount is easier. `accessutil.Canonical`, `FilesVFS`, and `Access.Check` are already the single path and access checks. Mutations already go through `fileutil` so events, access rows, and photo rows stay in one place.

## Leave these alone

- `featureflagutil`. The registry is an empty slice on purpose after the chat, calendar, and slides flags were migrated out. The settings routes still return that empty list. `RequireFeatureEnabled` is the gate the next flag will use.
- `cmd/lsusb`, `cmd/knowledge`, `cmd/provisioning`, and the Tailscale bridge command (`packages/tailnet_flutter/cmd/tsnetbridge`). The mobile build calls the bridge.
- `pkg/backup/sync.go` `DrainPending`. Only tests call it, and the worker loop never does. That is a missing call, so a failed mirror stays queued. Do not delete it.
- `ExportChat`, `ImportChat`, `ExportVault`, `ImportVault`. Snapshots use the ciphertext path. The wrappers are the restore API. `RestoreVault` and `RestoreChat` call `ImportVault` and `ImportChat` for the restore routes.
- `authutil/wordlist.go`. The server no longer draws phrases. The Dart recovery-phrase test reads this file and checks it against the Dart list.
- The `ponytail:` notes. They are recorded shortcuts (one backup at a time, chat marker queries, session renewal), not narration.
- `scripts/check-go-structure.bash` allowlists. Every entry still matches a live call.
- `trashutil`. It is thin on purpose: namespace, `Trasher`, event. The handler should not know the trash layout.
- `StorageServiceVFS` versus `LocalVFS`. List fans out across managed roots. Open, Write, and Delete already delegate to the host helpers.
- Auth, access, archive limits, and the files integration tests.
- SQL that only tests in another package call (`CountActiveAdmins`, `GetConnectedDevice`, `CountConnectedDevices`, `GetDeviceName`, `DeleteDeviceRole`, `GetMusicTrackScanState`, `ListRootAlbums`). Those tests are the callers.

`GetFileContent` is the one query confirmed to have no caller outside generated sqlc. The other query names that look unused are called from tests in another package.

## Order of work

1. Dead helpers in pass 1. One mechanical change. Run the package tests you touch.
2. Files access helper, `grantOwner`, and the export and convert twins.
3. Namespace lookup collapsed onto `FilesVFS`, with the error mapping kept at each edge.
4. The named test trims.
5. PPTX and XLSX onto `officezip`, with their existing limits passed in.
6. Decide on `odputil`, `odsutil`, `xlsutil`, and `DBVFS` before touching them.

Passes 1 through 4 are a few thousand lines. Pass 5 is a few hundred and can reject workbooks if the limits are wrong. Step 6 is the only place the line count moves by a lot, and it is a product decision.
