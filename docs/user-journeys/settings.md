# Settings Journeys

Covers the Settings page (`/settings`) — host management, theme, version updates, remote access, connected devices, and sign out.

---

### JN-ST-001: View settings page

**Preconditions:** User is logged in.

**Steps:**

1. Navigate to `/settings`.

**Expected result:**

- Settings page loads with all sections visible: hosts, theme, version, remote access, connected devices, storage devices, network drive, SBOM, help.

---

### JN-ST-002: Add a new quark host

**Preconditions:** User is on the Settings page.

**Steps:**

1. Tap **Add host** (or the `+` button in the hosts section).
2. Enter the host URL.
3. Confirm.

**Expected result:**

- New host appears in the hosts list.
- App can be switched to connect to the new host.

---

### JN-ST-003: Switch active host

**Preconditions:** Multiple hosts are configured.

**Steps:**

1. Navigate to `/settings`.
2. Tap a non-active host in the list.

**Expected result:**

- Active host changes.
- App begins using the new host for all API calls.

---

### JN-ST-004: Edit an existing host

**Preconditions:** At least one host is configured.

**Steps:**

1. Navigate to `/settings`.
2. Tap the edit action on a host entry.
3. Modify the URL or label.
4. Confirm.

**Expected result:**

- Host entry reflects the updated values.

---

### JN-ST-005: Remove a host

**Preconditions:** At least two hosts are configured (to avoid removing the only one).

**Steps:**

1. Navigate to `/settings`.
2. Tap the remove/delete action on a non-active host.
3. Confirm.

**Expected result:**

- Host is removed from the list.
- Active host is unchanged.

---

### JN-ST-006: Toggle app theme (light / dark / system)

**Preconditions:** User is logged in.

**Steps:**

1. Locate the theme toggle (app bar icon or settings section).
2. Tap to cycle through light → dark → system (or select from a picker).

**Expected result:**

- UI theme changes immediately.
- Setting is persisted across app restarts.

---

### JN-ST-007: View installed version

**Preconditions:** User is on the Settings page.

**Steps:**

1. Scroll to the version section.

**Expected result:**

- Installed version string is displayed.

---

### JN-ST-008: Check for available updates

**Preconditions:** User is on the Settings page. Quark can reach the update source.

**Steps:**

1. Scroll to the version/update section.
2. Tap **Check for updates** (or wait for it to load automatically).

**Expected result:**

- A list of available versions is shown.
- The current installed version is indicated.

---

### JN-ST-009: Update to a new version

**Preconditions:** A newer version is available (JN-ST-008).

**Steps:**

1. Select the target version from the dropdown or list.
2. Tap **Update**.

**Expected result:**

- Update process begins with a progress indicator.
- On completion, the installed version reflects the new version.

---

### JN-ST-010: Enable auto-update

**Preconditions:** User is on the Settings page.

**Steps:**

1. Find the auto-update toggle.
2. Enable it.

**Expected result:**

- Auto-update is enabled on the quark.
- Toggle reflects the enabled state.

---

### JN-ST-011: Enable remote access

**Status:** Experimental. The Quark cannot fetch its own Tailscale auth key yet, so from the app this journey
currently ends at the error below (#1815).

**Preconditions:** User is signed in as an admin and on the Settings page. Remote access is currently disabled.

**Steps:**

1. Scroll to the Remote Access section, which is marked **Experimental**.
2. Tap **Enable remote access**.

**Expected result:**

- Today: a snackbar says remote access needs an auth key and automatic provisioning is not available yet.
- A non-admin is told they do not have permission.
- Once a key is supplied, remote access is enabled and the section reads **Connecting…** until the node joins
  the tailnet, then **Connected via Tailscale** with the remote URL.
- If the Quark cannot start remote access, at boot or on enable, the section stays on and says it could not
  start; the reason is in the Quark's log.

---

### JN-ST-012: Disable remote access

**Preconditions:** User is signed in as an admin. Remote access is currently enabled.

**Steps:**

1. Navigate to `/settings` → Remote Access.
2. Tap **Disable**.

**Expected result:**

- Remote access is disabled.
- Remote URL is no longer shown.
- The Quark logs its node out of the tailnet and forgets the enrollment, so enabling again needs a new key.

---

### JN-ST-013: Copy remote access URL

**Preconditions:** Remote access is enabled (JN-ST-011).

**Steps:**

1. Tap the copy button next to the remote URL.

**Expected result:**

- URL is copied to the clipboard.
- A confirmation (snackbar or toast) is shown.

---

### JN-ST-014: View connected client devices

**Preconditions:** At least one device has connected to the quark.

**Steps:**

1. Navigate to `/settings`.
2. Scroll to the Connected Devices section.

**Expected result:**

- List of connected devices is shown with: request count, last-seen timestamp.

---

### JN-ST-015: Revoke a connected device

**Preconditions:** At least one connected device is listed (JN-ST-014).

**Steps:**

1. Tap **Delete** / revoke on a device.
2. Confirm.

**Expected result:**

- Device is removed from the list.
- That device must re-authenticate to access the quark.

---

### JN-ST-016: View storage devices in settings

**Preconditions:** At least one storage device is connected.

**Steps:**

1. Navigate to `/settings`.
2. Scroll to the Storage Devices section.

**Expected result:**

- Devices are listed with name and mount status.

---

### JN-ST-017: Mount a storage device from settings

**Preconditions:** An unmounted device is listed in settings.

**Steps:**

1. Tap **Mount** on the unmounted device.

**Expected result:**

- Device mounts and status updates.
- See also JN-SD-003.

---

### JN-ST-018: Rename a storage device from settings

**Preconditions:** A storage device is listed.

**Steps:**

1. Tap the rename action.
2. Enter a new name.
3. Confirm.

**Expected result:**

- Device name is updated everywhere in the UI.
- See also JN-SD-006.

---

### JN-ST-020: View Software Bill of Materials (SBOM)

**Preconditions:** User is on the Settings page.

**Steps:**

1. Scroll to the **Software Bill of Materials** section.
2. Expand the Go dependencies tile.
3. Expand the Flutter packages tile.

**Expected result:**

- Both sections list their respective packages with version numbers.

---

### JN-ST-021: Adjust auto-refresh interval

**Preconditions:** User is on the Settings page.

**Steps:**

1. Find the refresh interval setting.
2. Change the interval (e.g. from 15 s to 30 s).

**Expected result:**

- The new interval is applied to auto-refreshing pages (health, devices, etc.).

---

### JN-ST-022: Sign out from settings

**Preconditions:** User is logged in.

**Steps:**

1. Navigate to `/settings`.
2. Tap **Sign out**.
3. Confirm if prompted.

**Expected result:**

- Session is cleared.
- App redirects to `/login`.
- See also JN-AUTH-007.
