# Settings Journeys

Covers the Settings page (`/settings`) — host management, theme, version updates, remote access, connected devices, and sign out.

Settings is split into tabs, each with its own URL (#2350). `/settings` redirects to `/settings/general`, and an
unknown tab lands on General too. Admins get a sixth tab, Features, while the Quark has a feature in beta (#2542).

| Tab | URL | Holds |
| --- | --- | --- |
| **General** | `/settings/general` | Backend hosts, theme, theme color, auto-refresh interval, demo mode, a link to the drives |
| **Account** | `/settings/account` | Sign out, your sessions, then an **Account and data** row at the bottom that leads to Delete account and (admins) Reset this Quark |
| **Network** | `/settings/network` | Remote access, connected devices, SSH access (admins) |
| **Updates** | `/settings/updates` | The Quark's version, updates and automatic updates (admins), Repair installation (admins) |
| **About** | `/settings/about` | The app's version, Help & Support, Terms of Service, the software bill of materials |
| **Features** | `/settings/features` | A switch per beta feature, such as Chat (admins, only while a beta exists) |

---

### JN-ST-001: View settings page

**Preconditions:** User is logged in.

**Steps:**

1. Navigate to `/settings`.
2. Tap each tab in turn.
3. Use the browser's Back button.
4. Reload the page.

**Expected result:**

- Step 1 lands on `/settings/general`, the General tab.
- Each tab in step 2 changes the address bar to its own URL (the table above) and shows that tab's sections.
- Back returns to the previous tab.
- A reload, or opening any tab's URL directly, shows that same tab.
- Nothing destructive is on any tab. Delete account and Reset this Quark sit behind the **Account and data** row at
  the bottom of the Account tab, below Sign out (JN-ST-026, JN-ST-027).
- While the Quark cannot be reached, a banner at the top of every tab says so.

---

### JN-ST-002: Add a new quark host

**Preconditions:** User is on the General tab of Settings (`/settings/general`).

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

1. Navigate to `/settings/general`.
2. Tap a non-active host in the list.

**Expected result:**

- Active host changes.
- App begins using the new host for all API calls.

---

### JN-ST-004: Edit an existing host

**Preconditions:** At least one host is configured.

**Steps:**

1. Navigate to `/settings/general`.
2. Tap the edit action on a host entry.
3. Modify the URL or label.
4. Confirm.

**Expected result:**

- Host entry reflects the updated values.

---

### JN-ST-005: Remove a host

**Preconditions:** At least two hosts are configured (to avoid removing the only one).

**Steps:**

1. Navigate to `/settings/general`.
2. Tap the remove/delete action on a non-active host.
3. Confirm.

**Expected result:**

- Host is removed from the list.
- Active host is unchanged.

---

### JN-ST-006: Toggle app theme (light / dark / system)

**Preconditions:** User is logged in.

**Steps:**

1. Locate the theme button in the app bar; it is the one control for the theme (#2053).
2. Tap to cycle through matching the device → light → dark → matching the device. The tooltip names the
   current mode and the next one.

**Expected result:**

- UI theme changes immediately.
- The Theme row on the General tab of Settings shows the mode in effect and follows each tap.
- Setting is persisted across app restarts.

---

### JN-ST-007: View installed version

**Preconditions:** User is on the Updates tab of Settings (`/settings/updates`).

**Steps:**

1. Find the **Quark version (installed)** card.

**Expected result:**

- Installed version string is displayed.

---

### JN-ST-008: Check for available updates

**Preconditions:** User is on the Updates tab of Settings (`/settings/updates`). Quark can reach the update source.

**Steps:**

1. Find the **Quark version (installed)** card.
2. Tap **Check for updates** (or wait for it to load automatically).

**Expected result:**

- A list of available versions is shown.
- The current installed version is indicated.

---

### JN-ST-009: Update to a new version

**Preconditions:** User is signed in as an admin. A newer version is available (JN-ST-008).

**Steps:**

1. Select the target version from the dropdown or list.
2. Tap **Update**.

**Expected result:**

- Update process begins with a progress indicator.
- On completion, the installed version reflects the new version.

---

### JN-ST-010: Enable auto-update

**Preconditions:** User is signed in as an admin and on the Updates tab of Settings (`/settings/updates`).

**Steps:**

1. Find the auto-update toggle.
2. Enable it.

**Expected result:**

- Auto-update is enabled on the quark.
- Toggle reflects the enabled state.

---

### JN-ST-011: Enable remote access

**Preconditions:** User is signed in as an admin and on the Network tab of Settings (`/settings/network`). Remote access is currently off. The app is a debug or profile build: release builds say **Coming soon** until the app can run its own tunnel (#2857, #2876).

**Steps:**

1. Find the Remote access section.
2. Tap **Set up remote access**.
3. Tap **Turn on remote access** in the sheet.
4. Wait, or close the sheet partway.

**Expected result:**

- Step 2 opens a sheet saying what remote access does, with **Turn on remote access** and **Not now**, and that it
  comes with the Quark: no extra account, no subscription, nothing else to install. Nothing in the flow names
  Tailscale, a tailnet, a key, or an address (#2857).
- The Quark fetches its own key from the provisioning service; the user never sees or enters a key
  (#1876). The first enable creates the Quark's own household on the tailnet and joins it under a hostname
  unique to the device; enabling again after a disable rejoins the same household (#2358).
- After step 3 the sheet shows a checklist: *Preparing a private connection*, then *Connecting your Quark*, then
  every step ticked and **Remote access is on** with **Done**. It moves by itself as the Quark reports its state,
  every few seconds, with no reload.
- Closing the sheet partway leaves setup running. The section reads **Connecting…**, then **On**, with *Reachable
  away from home*. The remote address is never shown (the app keeps it for its own routing, #1880).
- A non-admin sees what remote access is and that an admin turns it on for the household, with no button and no
  directions to the page they are already on (#2901).
- If the Quark cannot start remote access, at boot or on enable, or the tailnet rejects its key, the sheet closes
  and the section says **Couldn't connect**: it is still switched on, the Quark keeps trying, and it lists what to
  try, with **Try again**, **Turn off** and **Get help**, which opens the support page in the browser and leaves the
  section where it is (#2902). The reason is in the Quark's log, never on screen.
- After a restart the Quark reconnects with its saved enrollment and does not fetch a new key.

---

### JN-ST-012: Disable remote access

**Preconditions:** User is signed in as an admin. Remote access is currently enabled.

**Steps:**

1. Navigate to `/settings/network`, the Remote access section.
2. Turn the **Your Quark** switch off.
3. Tap **Cancel**, then turn the switch off again and tap **Turn off**.

**Expected result:**

- Step 2 asks **Turn off remote access for everyone?** and says what that does: devices away from home lose the
  Quark, home keeps working, and added devices stay added.
- **Cancel** leaves remote access on.
- **Turn off** turns remote access off, says so in a snack bar, and the section offers **Set up remote access**
  again.
- The Quark logs its node out of the tailnet and keeps its machine key, so enabling again rejoins as the same node.
- A non-admin sees the switch on but cannot move it.

---

### JN-ST-013: Copy remote access URL (retired)

Retired by #2857: Settings no longer shows the remote address. The app keeps it for its own routing (#1880), and
nobody needs to type or paste it.

---

### JN-ST-014: View connected client devices

**Preconditions:** At least one device has connected to the quark.

**Steps:**

1. Navigate to `/settings/network`.
2. Find the Connected devices section.

**Expected result:**

- List of connected devices is shown with: request count, last-seen timestamp.

---

### JN-ST-015: Revoke a connected device

**Preconditions:** User is signed in as an admin. At least one connected device is listed (JN-ST-014).

**Steps:**

1. Tap **Delete** / revoke on a device.
2. Confirm.

**Expected result:**

- Device is removed from the list.
- That device must re-authenticate to access the quark.

---

### JN-ST-016: Open storage devices from settings

**Preconditions:** A Quark is configured.

**Steps:**

1. Navigate to `/settings/general`.
2. Tap **Storage devices**.

**Expected result:**

- The System page opens on its Storage tab (`/system/storage`), listing the drives (JN-SD-001).
- Settings keeps no drive list of its own (#2350): viewing, mounting and renaming drives happen on the System page's Storage tab.

---

### JN-ST-017: Mount a storage device from settings

**Status:** Retired (#2350). Mounting is on the System page's Storage tab, JN-SD-003.

---

### JN-ST-018: Rename a storage device from settings

**Status:** Retired (#2350). Renaming is on the System page's Storage tab, JN-SD-006.

---

### JN-ST-020: View Software Bill of Materials (SBOM)

**Preconditions:** User is on the About tab of Settings (`/settings/about`).

**Steps:**

1. Find the **Software Bill of Materials** section.
2. Expand the Go dependencies tile.
3. Expand the Flutter packages tile.

**Expected result:**

- Both sections list their respective packages with version numbers.

---

### JN-ST-021: Adjust auto-refresh interval

**Preconditions:** User is on the General tab of Settings (`/settings/general`).

**Steps:**

1. Find the refresh interval setting.
2. Change the interval (e.g. from 15 s to 30 s).

**Expected result:**

- The new interval is applied to auto-refreshing pages (health, devices, etc.).

---

### JN-ST-022: Sign out from settings

**Preconditions:** User is logged in.

**Steps:**

1. Navigate to `/settings/account`.
2. Tap **Sign out**, the first entry on the tab.
3. Confirm if prompted.

**Expected result:**

- Session is cleared.
- App redirects to `/login`.
- See also JN-AUTH-007.

---

### JN-ST-023: Toggle demo mode

**Preconditions:** User is on the General tab of Settings (`/settings/general`). No quark needs to be configured.

**Steps:**

1. Find the **Demo mode** toggle.
2. Enable it.
3. Navigate to `/photos`.

**Expected result:**

- The Photos page shows the bundled sample photos and albums (`assets/demo/`) instead of the quark's library, and
  makes no request to the quark for them.
- Sample photos open in the image viewer, can be starred (locally only), and their albums open in place on the
  Photos page from the sidebar (JN-PH-012), with **All photos** returning to the sample library.
- Album creation, renaming, deletion, and adding sample photos to albums are disabled.
- The setting persists across app restarts.
- Switching the toggle off returns the Photos page to the quark's real library with nothing from the sample set
  rendered.

---

### JN-ST-024: Turn SSH access on and off

**Preconditions:** Logged in as an admin (JN-AUTH-002). The Quark runs as its installed service (`sudo quark install`)
with `openssh-server` installed, as on every Quark image. SSH access starts off.

**Steps:**

1. Navigate to `/settings/network` and find **SSH access**.
2. Tap **Add key**, paste a public key (the contents of `~/.ssh/id_ed25519.pub`), and tap **Add key**.
3. Optionally tap **Set password**, type a password of at least 12 characters twice, and tap **Set password**.
4. Switch **SSH access** on and confirm **Turn on**.
5. From a computer on the same network, run `ssh quark@quark.local`.
6. Try `ssh root@quark.local`.
7. Back in settings, remove the key with its delete button, tap **Clear password**, and switch **SSH access** off.

**Expected result:**

- The key appears under **Allowed keys** by its comment, with its SHA256 fingerprint.
- Step 4 asks for confirmation first; cancelling leaves SSH off.
- Step 5 signs in as `quark` with the key, or with the password when one is set.
- Step 6 is refused: root can never sign in over SSH.
- After step 7, port 22 is closed and nothing answers `ssh`. The switch stays where it was left across a reboot.
- On a Quark that can't manage SSH (not the installed service, no SSH server, or an install from before this
  feature), the section shows why and the command that fixes it, instead of the controls.

Root's password is locked on every Quark: `quark install` locks it, and so does every service start, so Armbian's
default root password never works. For a console login with a keyboard and monitor, sign in as `quark` with the
password set under **SSH access** — set one there first, and clear it afterwards.

**Notes:** Admin-only; other accounts don't see the section, and `/api/v0/ssh/*` answers them 403. Quark never
stores the password. Keys live in `/var/lib/quark/.ssh/authorized_keys`.

### JN-ST-025: Repair the installation

**Preconditions:** Logged in as an admin (JN-AUTH-002). The Quark runs on Linux as its installed service
(`sudo quark install`), with a unit from after #2120.

**Steps:**

1. Navigate to `/settings/updates` and find **Repair installation**.
2. Tap **Repair installation**, then **Cancel** in the confirmation.
3. Tap **Repair installation** again and confirm **Repair**.
4. Wait a few seconds, then reload the settings page.

**Expected result:**

- Step 2 does nothing; the confirmation says Quark will restart and be unavailable for a few seconds.
- Step 3 shows "Quark is restarting". The service exits, systemd starts it again, and the restart reapplies the
  system setup as root (the sudoers rule and the unit are rewritten).
- After step 4 the page loads normally again.
- On a Quark whose unit predates #2120, the section shows no button but the one-time command to run on the device,
  `sudo quark install`. After running it, the button appears.
- On a Quark that is not Linux or not the installed service, the section does not appear at all.

**Notes:** Admin-only; other accounts don't see the section, and `/api/v0/admin/repair` answers them 403. The button
asks for a restart and nothing more: no new privileges or sudoers entries.

### JN-ST-026: Delete your account

**Preconditions:** Logged in (JN-AUTH-002), as any account.

**Steps:**

1. Navigate to `/settings/account`. Below **Sign out**, tap **Account and data**.
2. Tap **Delete account**.
3. Type a wrong password and tap **Delete my account**.
4. Tap **Delete account** again, type your password and tap **Delete my account**.

**Expected result:**

- The Account tab shows no Delete account or Reset entry itself, only the **Account and data** row. It opens
  a page with a back button, not the drawer.
- Step 2 asks for your password, hidden with a show/hide toggle, and says your files stay on the Quark. The button
  stays disabled until something is typed.
- Step 3 shows "That password isn't right. Nothing was deleted." You stay signed in and nothing is deleted.
- Step 4 deletes the account, signs you out everywhere, and goes to `/login`, or to `/setup` when it was the last
  account.

**Notes:** Required by App Store Review Guideline 5.1.1(v): deletion starts in the app and is easy to find (#1762).
The password travels in the request body, never the URL, and attempts share the sign-in rate limit (#2346).

### JN-ST-027: Reset this Quark

**Preconditions:** Logged in as an admin (JN-AUTH-002).

**Steps:**

1. Navigate to `/settings/account` and tap **Account and data**.
2. Under **Reset**, tap **Reset this Quark**.
3. Choose what to erase, type your password and tap **Reset this Quark**.

**Expected result:**

- The **Reset** section sits below **Delete account**, under its own heading. Other accounts don't see it.
- Each entry says how far it reaches before it is tapped: **Delete account** removes only your account and leaves
  your files and other accounts; **Reset this Quark** erases every account, and names the **Quark data on attached
  drives** box as where attached drives are included.
- Step 2 offers **Accounts and settings** and **Stored files** checked, and **Quark data on attached drives**
  unchecked, and reads back what the reset erases and keeps. Nothing can be sent without a password and at least
  one box.
- A wrong password shows "That password isn't right. Nothing was deleted."
- The right one erases what was chosen and returns the Quark to first-boot setup.

---

### JN-ST-028: Turn a beta feature off

**Preconditions:** Logged in as an admin (JN-AUTH-002). A second, non-admin account is signed in on another device.
The Quark has at least one feature in beta, such as Chat.

**Steps:**

1. Navigate to `/settings/features`.
2. Turn off a feature, say **Chat** (marked **Beta**).
3. On the member's device, open the drawer, then open the feature's page directly (`/chat`).

**Expected result:**

- Each beta shows its name, a **Beta** badge, what turning it off does, and a switch. The switch holds still until the
  Quark has saved it.
- The member's drawer loses the feature's row without a reload, and a member already on its page is moved to Files.
- Opening the page directly goes to Files.
- Turning it back on brings the row back for everyone. The copy says so plainly: turning a beta off hides it and keeps
  its stored data.

**Notes:**

- Non-admins get no Features tab, and `/settings/features` sends them to Files. With no feature in beta, admins get no
  Features tab either.
- A refused change says so ("Couldn't change the feature…") and leaves the switch where it was.

---

### JN-ST-029: See and sign out your sessions

**Preconditions:** User is logged in.

**Steps:**

1. Navigate to `/settings/account`.
2. Find the **Sessions** card under **Sign out**.
3. Tap the sign-out button on a session other than **This session** and confirm.
4. Tap **Sign out everywhere else** and confirm.
5. Tap the sign-out button on **This session** and confirm.

**Expected result:**

- The card lists every session of the account with when it signed in and when it was last used, and marks the one
  in use as **This session**.
- After step 3 that session is gone from the list, and whoever was using it has to sign in again.
- After step 4 only **This session** is left, and **Sign out everywhere else** is disabled.
- Step 5 signs out the same way **Sign out** does (JN-ST-022): the session is cleared and the app goes to `/login`.
- A failure shows a "Couldn't ..." sentence in the card and leaves the list as it was.

---

### JN-ST-030: Add a Quark by name on a router that appends `.lan`

**Preconditions:** The Quark is on the same Wi-Fi as the phone. The router registers it in its own DNS as
`quark.lan`, and the phone cannot resolve `quark.local` (Android before 12, for one).

**Steps:**

1. Open **Add host** (JN-ST-002), or the first-run **Connect to your Quark** form on the login page.
2. Type `quark.local`, `quark.lan`, `quark.local.lan` or plain `quark`, and save.

**Expected result:**

- The Quark is added whichever of those forms was typed, as long as one of `quark.local`, `quark.lan` or `quark`
  answers. The address saved is the one that answered, so a typed `quark.local` is stored as `https://quark.lan`.
- The typed address is tried first; the other names are only tried when it does not answer (#2518).
- An IP address, a public name and `localhost` are tried exactly as typed.
- When no name answers, the form says it couldn't connect and keeps what was typed, so the user can enter the IP
  address shown on the device instead.

---

### JN-ST-031: Pick a theme color

**Preconditions:** Logged in as an admin (JN-AUTH-002). A second, non-admin account is signed in on another device.

**Steps:**

1. As the member, navigate to `/settings/general` and find **Theme color**, below **Theme**.
2. Tap a swatch, then drag the hue slider for a custom color.
3. As the admin, find **This Quark's default** on the same tab and tap a swatch.
4. As the member, tap **Use this Quark's default**.
5. Sign out as the member.

**Expected result:**

- The whole theme follows the picked color at once, in light and dark mode: the app bar and the drawer take a
  clearly colored tone of it, page backgrounds and cards a faint tint, and buttons, selection, focus rings and
  switches a stronger tone of the same hue. Only the hue of a custom color is kept, so every surface stays legible.
- **Classic**, the first swatch, is Quark as it ships: neutral surfaces with the blue accent. A Quark where nobody
  has picked a color looks that way.
- After step 3 the member's color does not change: their own choice wins. After step 4 it becomes the admin's
  choice, and later changes to the Quark's default reach them without a reload.
- The sign-in page keeps the color the member last saw on this Quark. A Quark the app has never signed in to shows
  that Quark's default.
- The theme color belongs to the account and the Quark: the same account on another device gets the same color, and
  switching hosts (JN-ST-003) switches color with it. Light, dark and system mode stay per device (JN-ST-006).

**Notes:**

- Non-admins get no **This Quark's default** section, and the Quark refuses the change from them.
- A refused change says so ("Couldn't save your theme color…") and puts the previous color back.

---

### JN-ST-032: See how the app reaches the Quark from any page

**Preconditions:** The mobile app is signed in to a Quark (the indicator never shows on web).

**Steps:**

1. On any main page, tap the connection indicator at the end of the app bar (home, cloud, or crossed-out cloud).
2. Read the sheet, then tap **Your Quark**.

**Expected result:**

- Step 1 opens a **Connection** sheet saying, in plain words, whether the app is talking to the Quark on the home
  network, through remote access, or can't reach it at all, with what that means (#2857).
- The **Your Quark** row says whether remote access is on, off, connecting, or couldn't connect. When the Quark
  is still being asked it says *Checking remote access…*, and when it can't be asked it says it couldn't load the
  status (#2904).
- Step 2 closes the sheet and opens `/settings/network`.
- Nothing in the sheet names Tailscale, an address, or a raw error.
