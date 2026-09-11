# Quark User Journeys

This directory documents user journeys for Quark — the workflows a real user would perform when using the app. These serve three purposes:

1. **Manual testing** — step-by-step scripts a tester can follow
2. **Feature inventory** — explicit record of what the app is supposed to do
3. **Automated tests** — ground truth for future E2E/integration test coverage

## Structure

Each file covers one feature area. Journeys within a file follow a consistent format:

```
### JN-XXX: Journey Title

**Preconditions:** What must be true before starting.
**Steps:** Numbered steps the user takes.
**Expected result:** What success looks like.
**Notes:** Edge cases, automation hints, related journeys.
```

Journey IDs are stable — don't renumber when adding new ones.

## Files

| File                                     | Feature Area                                           |
| ---------------------------------------- | ------------------------------------------------------ |
| [auth.md](auth.md)                       | Setup, login, logout, recovery                         |
| [file-browser.md](file-browser.md)       | file browser (browse, upload, download, manage) |
| [photos.md](photos.md)                   | Photos, albums, favorites                              |
| [trash.md](trash.md)                     | Trash (browse, restore, delete permanently, empty)     |
| [docs.md](docs.md)                       | Document editor (.qdoc files)                         |
| [sheets.md](sheets.md)                   | Spreadsheet editor (.qsheet files)                    |
| [vault.md](vault.md)                     | Password vault (setup, entries, import/export)         |
| [health.md](health.md)                   | System health dashboard                                |
| [storage-devices.md](storage-devices.md) | Storage device management                              |
| [settings.md](settings.md)               | App settings, hosts, updates, remote access            |

## Conventions

- **"butler"** refers to the Quark server/device.
- **"app"** refers to the Flutter client (web, mobile, or desktop).
- Steps use present tense: "Tap", "Enter", "Navigate to".
- Expected results describe UI state, not implementation internals.
- Preconditions reference other journey IDs where setup is needed.
