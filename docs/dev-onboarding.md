# Dev Onboarding

Get Quark running locally in about 10 minutes.

## Prerequisites

You need: Go, Flutter, Make, [air](https://github.com/air-verse/air), sqlc, swag.

The Makefile installs most of these for you:

```bash
make setup
```

This runs `setup/gotools`, `setup/air`, `setup/sqlc`, `setup/swag`, and `setup/flutter` in one shot. If you only
need the backend (no Flutter), run `make setup/gotools setup/air setup/sqlc setup/swag` instead.

### Shared agent skills

Skills that are not specific to Quark — `autobutler:resolve-issue`, `autobutler:gh-stack` — live in
[autobutler-org/agent-plugins](https://github.com/autobutler-org/agent-plugins), a Claude Code plugin shared by
every repository in the org. `.claude/settings.json` names the marketplace and enables the plugin, so Claude Code
offers to install it the first time you open the repository; accept the prompt. To install it by hand:

```text
/plugin marketplace add autobutler-org/agent-plugins
/plugin install autobutler@autobutler-org
```

Skills about this codebase (`architecture`, the `quark-widgets-*` pair) stay in `.claude/skills/`.

## Clone and build

```bash
git clone https://github.com/autobutler-org/quark.git
cd quark
make setup
make generate
make build
```

`make generate` runs sqlc and swag to produce generated files. Run it after any database schema change or API
annotation change. The CI will fail if you forget — it checks for a clean working tree after running `make
generate`.

## Run the backend

There are two modes, and they differ in both scheme and port. Pick one explicitly:

```bash
make watch/backend         # plain HTTP  on http://localhost:8080
make watch/backend/secure  # HTTPS       on https://localhost (:443)
```

Both hot-reload via air — edit Go files and the server restarts automatically. The `serve/backend` and
`serve/backend/secure` targets are the same two modes without the file watcher.

Which one you want depends on what you're working on:

| | `watch/backend` | `watch/backend/secure` |
| --- | --- | --- |
| URL | `http://localhost:8080` | `https://localhost` (:443) |
| TLS | none | self-signed, generated on first boot into `<dataDir>/certs/` |
| `curl` | works as-is | needs `-k` (the cert is not in any trust store) |
| Root needed | no | on Linux, yes — `:443` is privileged |

The self-signed certificate is never added to your system trust store. The Flutter client opts out of chain
verification for private and loopback addresses, and for a local name (`quark.local`, `quark.lan`) only once it is
the Quark you chose, so it can talk to it; browsers and `curl` will still warn.

To serve a certificate of your own instead, pass `quark serve --tls-cert <path> --tls-key <path>`, or set
`QUARK_TLS_CERT` and `QUARK_TLS_KEY`. Nothing is written to `<dataDir>/certs/` then, and replacing the pair on
disk is picked up by the next connection. Both are needed, and neither goes with `--insecure`.

If you need root — for USB device mounting on Linux, or to bind `:443` in secure mode — prefix any backend
target with `AS_ROOT=1`, which runs it under `sudo`:

```bash
make watch/backend AS_ROOT=1
make watch/backend/secure AS_ROOT=1
```

## Run the frontend

Web:

```bash
make serve/frontend
```

Serving to a browser on another machine? Use `make serve/frontend FLUTTER_BUILD_MODE=release`. The default
debug build ships thousands of unbundled modules and is very slow over a network; release serves one minified
bundle, at the cost of hot reload.

Mobile (pick an emulator first):

```bash
make emulate          # default platform
make emulate/android  # or emulate/ios
make serve/frontend/mobile
```

Linux desktop:

```bash
make build/frontend/linux LINUX_ARCH=x64  # release bundle; LINUX_ARCH=arm64 for aarch64
./build/linux/x64/release/bundle/quark
flutter run -d linux                       # or run it with hot reload
```

The bundle is the `quark` binary plus its `lib/` and `data/` directories; move them together. The build needs
Ninja, CMake, Clang, pkg-config, and the development files of GTK 3, libsecret, libmpv, FFmpeg and libjpeg:

```bash
# Arch / Omarchy: gtk3, libsecret, clang, cmake and pkg-config are usually already installed
sudo pacman -S --needed ninja gtk3 libsecret mpv ffmpeg libjpeg-turbo clang cmake pkgconf

# Debian / Ubuntu: linux/apt-packages.txt is the list CI installs, the AppImage tools included
xargs sudo apt-get install < linux/apt-packages.txt
```

The first build downloads PDFium (for `pdfrx`) and compiles libsodium (for `sodium`), so it needs network access
and takes a few minutes; later builds reuse both.

The run-time packages are listed under [Linux runtime dependencies](#linux-runtime-dependencies).

## Running Quark as a Linux desktop app

`make install/frontend/linux` builds the release bundle for this machine's architecture and installs it for your
user, with no `sudo`. Quark then shows up in the launcher (Super and type "quark" on Omarchy, or the GNOME and KDE
app grids) and opens in its own window with its icon.

```bash
make install/frontend/linux      # bundle in ~/.local/share/quark-app, launcher entry and icons under ~/.local/share
make uninstall/frontend/linux    # removes all of it
```

Run it again to upgrade in place. Set `PREFIX=<dir>` to install somewhere other than `~/.local`. A `quark`
symlink goes in `$PREFIX/bin`, and the launcher entry points at it by absolute path, so `~/.local/bin` does not
have to be on your `PATH`. The window class is `org.autobutler.quark`, which `linux/quark.desktop` carries as
`StartupWMClass` so Hyprland and docks match the window to its launcher entry. The installed app still needs the
[Linux runtime dependencies](#linux-runtime-dependencies).

## Building the Linux AppImage

The AppImage is the release bundle and the libraries it links, in one executable file that runs without an
install. A tagged release builds it for x86_64 and aarch64 in the `release-linux` job, one runner per
architecture, and attaches both to the GitHub release; the `build-linux` job builds both on every pull request
that touches the Linux app and keeps them as the `linux-appimage-x64` and `linux-appimage-arm64` artifacts.

```bash
make build/frontend/linux/appimage LINUX_ARCH=x64   # build/appimage/quark-v<version>-x86_64.AppImage and its .zsync
make build/frontend/linux/appimage LINUX_ARCH=arm64 # build/appimage/quark-v<version>-aarch64.AppImage and its .zsync
```

The version is the most recent git tag, or `BUILD_NAME=X.Y.Z`. `LINUX_ARCH` is required: `x64` or `arm64`.

The target builds with [appimage-builder](https://appimage-builder.readthedocs.io), which
`make setup/appimage-builder` installs at the pinned version into `~/.local/bin` (`PREFIX=<dir>` puts it in `<dir>/bin`). The build has to happen on
Ubuntu 22.04 of the target architecture: the recipe, `linux/AppImageBuilder.yml`, fills the AppImage with libraries from that
release's apt archive, and they have to be the ones the binary was linked against. Where it runs depends on the
host:

- **Ubuntu 22.04 of the same architecture** builds natively. That is what CI's runners are, one per
  architecture. `make setup/appimage-builder` installs the release AppImage on x86_64; on aarch64, which that
  release has no AppImage for, it installs the same version from PyPI into a venv, hash-locked by
  `linux/appimage-builder-requirements.txt`.
- **macOS** builds in Docker, so Docker Desktop has to be running. The same command builds the image from
  `linux/Dockerfile` (Ubuntu 22.04 with the packages in `linux/apt-packages.txt`, the Flutter version
  `pubspec.yaml` pins, and appimage-builder) for `LINUX_ARCH`'s platform, copies the working tree into a container and runs the same target
  there. Only `build/appimage/` is shared with the container, so nothing else in your checkout changes.
  On Apple silicon an arm64 container runs natively and an x64 one is emulated, so expect x64 to be slow; every
  run compiles from scratch.
- **Any other Linux** stops with an explanation; take the artifact from a pull request instead.

What the AppImage carries, so the host does not need it: GTK 3, libsecret, libmpv, the FFmpeg libraries, and
everything those depend on down to glibc. What it still takes from the host: the graphics stack (Mesa or the
vendor's GL driver, X11 or Wayland), fonts, and the services in the list below other than libmpv.
xdg-desktop-portal, `xdg-open`, avahi-daemon and a keyring are programs the app talks to, not libraries it can
bring along. The recipe's `test:` cases start the AppImage in Docker containers against a local X server; the make
target skips them, and they are there for running `appimage-builder` by hand on a Linux desktop.

## Linux runtime dependencies

The build packages above are for compiling. Running the bundle also needs these on the machine. The
[AppImage](#building-the-linux-appimage) brings its own libmpv and needs the rest:

1. **libmpv**, for video and audio playback. Arch: `mpv`. Debian / Ubuntu: `libmpv-dev`.
2. **xdg-desktop-portal plus a desktop backend** (`xdg-desktop-portal-gtk`, `-kde`, `-gnome` or `-hyprland`).
   `file_picker`'s Linux save dialog uses only the XDG FileChooser portal, with no zenity or kdialog fallback, so
   without one saving a file shows "Couldn't download the file".
3. **xdg-utils** (`xdg-open`), for "Open with".
4. **avahi-daemon**, running, so the app can find Quarks on your network. Typing the address works without it.
5. **GNOME Keyring or KWallet**, running and unlocked. The app keeps its sign-in in the desktop keyring through
   the Secret Service. Without one the app still opens signed out, and signing in explains that the keyring is
   needed.

## Lint and test

```bash
make check          # full lint; CI runs this
make check/fast     # staged gofmt, dart format, and cspell; the pre-commit hook runs this
make test/unit/backend  # Go tests
make test/unit/frontend # Flutter tests
```

Run `make check` before pushing. CI runs it and will fail if the linter is unhappy. After `make setup/hooks`,
the pre-commit hook runs the shorter `make check/fast` on the staged files.

## Database changes

Quark uses SQLite with golang-migrate for schema migrations and sqlc for query generation.

1. Add a migration file in `internal/db/migrations/` (name it `NNN_description.up.sql` and `NNN_description.down.sql`)
2. Add queries to `sql/queries/`
3. Run `make generate` to regenerate `internal/db/*.sql.go`
4. Commit the generated files

Don't edit the generated files by hand — they'll be overwritten by `make generate`.

### PostgreSQL

SQLite is the default and needs nothing. To run against PostgreSQL instead, with Docker installed:

```bash
make serve/postgres                      # start the development database
make serve/backend DB_BACKEND=postgres   # or watch/backend
```

The server then runs on PostgreSQL. A few features answer `501` there for now; the
[list](architecture/data.md#what-does-not-work-on-postgresql-yet) names each with its issue.

[PostgreSQL for local development](architecture/postgres-dev.md) has the rest: the `DB_BACKEND` switch,
resetting the database, `psql`, and running both backends side by side.

## Project structure

```text
cmd/quark/         Entry point
internal/
  db/                   sqlc-generated database layer + migrations
  server/api/v0/        API handlers (one file per route group) — mounted at /api/v0
    albums/             Photo album CRUD
    files/              File browser and file-type listing
    favorites/          Favorites toggle, list, and check
    photos/             Photo listing, metadata, rotation
    thumbnails/         Thumbnail generation and cache
  server/middleware/    Gin middleware (auth, OTEL, etc.)
pkg/util/               Shared utilities
  authutil/             Auth: hashing, session tokens, recovery phrases
  favoritesutil/        Favorites toggle and smart-album sync logic
  serverutil/           HTTP helpers: Response type, WrapApiRoute, HttpError
  sqlutil/              DB helpers: FormatTime, NullInt64, NullStringPtr
  storageutil/          File system and device utilities
  updateutil/           Version/update logic
lib/                    Flutter frontend
  models/               Data models (FileNode, PhotoAlbum, etc.)
  pages/                UI pages (photos, docs, sheets, file browser, etc.)
  services/             API clients (FilesService, FavoritesService, etc.)
  utils/                Shared utilities (SafeSetStateMixin, path helpers)
  widgets/              Reusable components
    layout/             AppBar, drawer, brand button
    photos/             Album sidebar, album tree tile, photo grid
docs/                   This documentation
packages/data_table/    Pure-Dart headless spreadsheet engine (used by sheets editor)
sql/queries/            sqlc SQL queries
```

## Common Makefile targets

Run `make help` to see everything. The most common ones:

| Target                          | What it does                          |
| ------------------------------- | ------------------------------------- |
| `make watch/backend`            | Backend hot reload, http://localhost:8080 |
| `make watch/backend/secure`     | Backend hot reload, https://localhost |
| `make serve/frontend`           | Flutter web dev server                |
| `make serve/frontend/mobile`    | Flutter mobile (after `make emulate`) |
| `make emulate/android`          | Launch Android emulator               |
| `make emulate/ios`              | Launch iOS simulator                  |
| `make build/frontend/linux LINUX_ARCH=x64\|arm64` | Linux desktop release bundle |
| `make build/frontend/linux/appimage LINUX_ARCH=x64\|arm64` | Linux AppImage (Ubuntu 22.04) |
| `make install/frontend/linux` | Install the Linux desktop app into the launcher |
| `make uninstall/frontend/linux` | Remove it again |
| `make build`                    | Build everything                      |
| `make generate`                 | Regenerate sqlc + swagger             |
| `make generate/backend/sqlc`    | Regenerate DB layer only              |
| `make generate/backend/swagger` | Regenerate API docs only              |
| `make check`                    | Full lint + format check              |
| `make check/fast`               | Staged gofmt, dart format, and cspell (pre-commit hook) |
| `make format`                   | Auto-format code                      |
| `make test/unit/backend`        | Go unit tests with coverage           |
| `make test/unit/frontend`       | Flutter unit tests                    |
| `make test/integration/backend` | Go integration tests                  |
| `make tidy`                     | Tidy Go + Flutter dependencies        |
| `make serve/postgres`           | Start the development PostgreSQL      |
| `make clean/postgres`           | Stop it (`clean/postgres/data` resets) |

## Notes

- USB device mounting requires root on Linux, as does binding `:443` in secure mode (`AS_ROOT=1`)
- Swagger UI is at `http://localhost:8080/swagger` in insecure mode, or `https://localhost/swagger` in secure mode
- `make generate` must be run before committing schema or query changes — CI enforces this
