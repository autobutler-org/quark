# Chat Journeys

Covers the chat beta (#2414): opening a channel, sending and receiving
end-to-end encrypted messages, unlocking chat on web after a reload, waiting
for a channel key, an admin turning the beta off, and creating, sharing,
renaming, leaving and deleting channels (#2422).

---

### JN-CHAT-001: Open general

**Preconditions:** Signed in (JN-AUTH-002). An admin has not turned chat off (see JN-CHAT-006).

**Steps:**

1. Open the drawer from the brand button.
2. Tap **Chat**, which carries a **Beta** badge.

**Expected result:**

- The app goes to `/chat`, which lands on `general` and the address bar settles on `/chat/<general's id>`.
- The header reads `# general`. The channel list shows the channels the account belongs to, `general` first.
- On a wide window the channels, messages and members sit side by side; on a phone the messages fill the screen, the channel list opens as a drawer, and the members open as a sheet.

**Notes:**

- A link to a channel the account can't open, or one that no longer exists, lands on `general` rather than an error page.
- Reloading `/chat/<id>` reopens that channel.

---

### JN-CHAT-002: Send a message

**Preconditions:** JN-CHAT-001. The account can write in the channel.

**Steps:**

1. Type a message in the composer at the bottom.
2. Press Enter (desktop) or tap the send button.

**Expected result:**

- The message appears at the bottom straight away, before the Quark has answered.
- It stays in place once the Quark stores it.
- When sending fails, a row above the composer says the message wasn't sent, with **Retry** and **Discard**. Retry sends it again; Discard drops it.

**Notes:**

- A channel where the account can read but not send shows "You can read this channel but not send messages in it" in place of the composer.
- A channel the account only manages, holding `manage_members` or `manage_channel` without `read_messages`, shows "You are not a member of this conversation" in place of the messages and the composer. Its members are still listed.
- The author of a message, or a member with `delete_messages`, can delete it from the trash button on the message after confirming.
- The Quark stores ciphertext only; the text is encrypted on the device.

---

### JN-CHAT-003: Receive a message live

**Preconditions:** Two accounts in the same channel, each with it open (JN-CHAT-001), on two devices or browsers.

**Steps:**

1. On the first, send a message (JN-CHAT-002).
2. Watch the second.

**Expected result:**

- The message appears on the second within a moment, without a refresh, under the sender's name and picture.

**Notes:**

- If the second device was offline, the messages it missed arrive when it reconnects.
- Membership and key changes show as system lines, such as "ada gave bob Moderator". One whose signature can't be checked is marked unverified.

---

### JN-CHAT-004: Reload on web and unlock

**Preconditions:** Signed in on the web app with chat open (JN-CHAT-001).

**Steps:**

1. Reload the browser tab.
2. The chat page shows **Unlock your messages** with a password field in place of chat.
3. Enter the wrong password and tap **Unlock**.
4. Enter the account password and tap **Unlock**.

**Expected result:**

- Step 3 says the password doesn't unlock the messages, and chat stays locked.
- Step 4 shows the channel and its messages.

**Notes:**

- On iOS and Android the keys survive a restart, so this prompt only shows on the web.
- The password never leaves the browser for this; it only opens keys the browser already has.

---

### JN-CHAT-005: Wait for a channel key

**Preconditions:** An owner has just added the account to a private channel, and no other member has been online since.

**Steps:**

1. Open the channel from the channel list.

**Expected result:**

- Messages from before the account had the key read "Waiting for the key to read this message".
- The composer is replaced by "Waiting for a member to share the key to this channel."
- Once any member who has the key opens the app, the messages open and the composer returns, without a reload.

---

### JN-CHAT-006: An admin turns the beta off

**Preconditions:** Signed in as an admin.

**Steps:**

1. Open **Settings**, General tab.
2. Turn off **Chat** (marked **Beta**).
3. As another account, open the drawer, then open `/chat` directly.

**Expected result:**

- The drawer has no Chat row.
- `/chat` and any `/chat/<id>` go to Files.
- Every `/api/v0/chat/*` request answers 404.
- Turning **Chat** back on brings everything back as it was: no message, channel or key was deleted.

**Notes:**

- Only admins see the switch. Chat is on until an admin turns it off.

---

### JN-CHAT-007: Create a private channel shared with a group

**Preconditions:** Signed in, chat unlocked (JN-CHAT-001). A group, say `Family`, exists (JN-USR-016).

**Steps:**

1. On the chat page, tap **New channel** in the top bar.
2. Enter a name, say `family`, and a topic, then tap **Create**.
3. Tap the channel's settings (the gear beside its name), then **Members**.
4. Search for `Family`, leave **Member** chosen, and tap **Add**.

**Expected result:**

- Step 2 closes the dialog and goes to `/chat/<id>` for `# family`, with a lock and **Owner** in the channel list. The first line reads "<you> set up encryption for this channel".
- Step 4 lists `Family` as **Member** beside you as **Owner**, and the timeline reads "<you> gave Family Member".
- Members of `Family` see the channel in their list; one who opens it before they have the key sees JN-CHAT-005.

**Notes:**

- A name another channel already has, ignoring case, keeps the dialog open with "A channel with that name already exists. Pick another name."
- What a member may do is a set of permissions, picked with a preset: **Viewer** reads, **Member** also sends and reacts, **Moderator** also deletes other people's messages and manages members, and **Owner** also renames and deletes the channel. **Custom** opens a checkbox per permission; any set that matches no preset shows as Custom.
- Checkboxes and presets with permissions you don't hold are disabled, with "You can't grant a permission you don't have".

---

### JN-CHAT-008: Add a user to a channel

**Preconditions:** You hold **Manage members** on a private channel (JN-CHAT-007).

**Steps:**

1. Open the channel's settings, then **Members** (or the add button in the member list).
2. Search for an account, choose **Viewer**, and tap **Add**.

**Expected result:**

- The account is listed as **Viewer**, and the timeline reads "<you> gave <them> Viewer".
- They see the channel, can read it once their key arrives, and find the composer closed with "You can read this channel but not send messages in it".

---

### JN-CHAT-009: Remove a user and see the key rotate

**Preconditions:** You hold **Manage members** on a channel with another account in it (JN-CHAT-008).

**Steps:**

1. Open the channel's settings, then **Members**.
2. Tap the **x** on the account's row, then **Remove**.

**Expected result:**

- Before removing, the sheet says the channel's key will change and that they keep whatever they already downloaded.
- The row goes, and the timeline reads "<you> removed <them>".
- A moment later it reads "<you> made a new key for this channel": messages from now on are under a key the removed account never had.
- The removed account's channel list no longer has the channel.

**Notes:**

- You can remove or lower only someone who holds less than you do, unless you hold **Manage channel**. The channel's creator can be removed or lowered only by an admin. Rows you can't change show without controls.
- Clearing every box on a row removes it rather than saving an empty set.

---

### JN-CHAT-010: Give a user Moderator and watch them delete a message

**Preconditions:** You own a channel with two other accounts in it as **Member**, say `bob` and `carol`, and `carol` has sent a message.

**Steps:**

1. Open the channel's settings, then **Members**.
2. On `bob`'s row, choose **Moderator**.
3. As `bob`, open the channel and tap the trash button on `carol`'s message, then **Delete**.

**Expected result:**

- Step 2 shows `bob` as **Moderator**, and the timeline reads "<you> gave bob Moderator".
- In step 3 the message becomes "This message was deleted" for everyone in the channel.

**Notes:**

- Anyone can delete their own messages while they can read the channel. Without **Delete messages**, other people's messages have no trash button.

---

### JN-CHAT-011: Demote a user to Viewer and see the rotation line

**Preconditions:** A channel with `bob` as **Moderator** (JN-CHAT-010).

**Steps:**

1. Open the channel's settings, then **Members**.
2. On `bob`'s row, choose **Viewer**.
3. Then choose **Custom**, and clear **Read messages**, keeping **Manage members**. Confirm the warning.

**Expected result:**

- Step 2 needs no warning: `bob` keeps reading. The timeline reads "<you> gave bob Viewer", and `bob`'s composer closes with "You can read this channel but not send messages in it".
- Step 3 warns that the key will change first. The timeline reads "<you> changed what bob can do", then "<someone> made a new key for this channel".
- `bob` still sees the channel and its members, as a delegated manager, but its messages are replaced with "You are not a member of this conversation".

---

### JN-CHAT-012: Rename a channel and change its topic

**Preconditions:** You hold **Manage channel** on a channel, or are an admin.

**Steps:**

1. Open the channel's settings, then **Edit name and topic**.
2. Change either, then tap **Save**.

**Expected result:**

- The header and the channel list show the new name and topic, for every member, without a reload.

---

### JN-CHAT-013: Leave a channel

**Preconditions:** You were added to a channel yourself, not only through a group, and it isn't `general`.

**Steps:**

1. Open the channel's settings, then **Leave channel**.
2. Tap **Leave**.

**Expected result:**

- The app goes to `general`, and the channel is gone from your list.
- The members who stay see "<you> left the channel", then a new key.

**Notes:**

- `general` has no **Leave channel**, and neither does a channel you are in only through a group.
- The last holder of **Manage channel** can't leave while anyone else is still in it; the Quark says to give someone else **Manage channel** first.

---

### JN-CHAT-014: Delete a channel

**Preconditions:** You hold **Manage channel** on a channel other than `general`, or are an admin.

**Steps:**

1. Open the channel's settings, then **Delete channel**.
2. Type the channel's name, then tap **Delete**.

**Expected result:**

- **Delete** stays off until the name is typed exactly.
- The app goes to `general`, and the channel, its messages and its keys are gone for everyone.

**Notes:**

- `general` has no **Delete channel**, and its `everyone` row is shown in **Members** but can't be removed or changed there.

---

### JN-CHAT-015: An admin manages a channel they are not in

**Preconditions:** Signed in as an admin. Someone else owns a private channel the admin isn't in.

**Steps:**

1. Open the chat page's channel list.
2. Under **Other channels**, open the channel.

**Expected result:**

- The header, settings and members show, but no messages: the message pane and the composer read "You are not a member of this conversation".
- Settings offer **Edit name and topic**, **Members** and **Delete channel**.
