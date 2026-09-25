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

- A channel where the account can only read shows "You can read this channel but not write in it." in place of the composer.
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
- Membership and key changes show as system lines, such as "ada gave bob write access". One whose signature can't be checked is marked unverified.

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
4. Search for `Family`, choose **Can edit**, and tap **Share**.

**Expected result:**

- Step 2 closes the dialog and goes to `/chat/<id>` for `# family`, with a lock in the channel list. The first line reads "<you> set up encryption for this channel".
- Step 4 lists `Family` at **Can edit** under you as **Owner**, and the timeline reads "<you> gave Family write access".
- Members of `Family` see the channel in their list; one who opens it before they have the key sees JN-CHAT-005.

**Notes:**

- A name another channel already has, ignoring case, keeps the dialog open with "A channel with that name already exists. Pick another name."
- **Can view** lets a member read; **Can edit** also posts; **Owner** also manages the channel.

---

### JN-CHAT-008: Add a user to a channel

**Preconditions:** You own a private channel (JN-CHAT-007).

**Steps:**

1. Open the channel's settings, then **Members**.
2. Search for an account, choose **Can view**, and tap **Share**.

**Expected result:**

- The account is listed at **Can view**, and the timeline reads "<you> gave <them> read access".
- They see the channel, can read it once their key arrives, and find the composer closed with "You can read this channel but not write in it."

---

### JN-CHAT-009: Remove a user and see the key rotate

**Preconditions:** You own a channel with another account in it (JN-CHAT-008).

**Steps:**

1. Open the channel's settings, then **Members**.
2. Tap the **x** on the account's row.

**Expected result:**

- The row goes, and the timeline reads "<you> removed <them>".
- A moment later it reads "<you> made a new key for this channel": messages from now on are under a key the removed account never had.
- The removed account's channel list no longer has the channel.

**Notes:**

- Removing yourself or another owner, or making them less than owner, asks first. The Quark refuses it if nobody would be left owning the channel, unless an admin does it.

---

### JN-CHAT-010: Rename a channel and change its topic

**Preconditions:** You own a channel, or are an admin.

**Steps:**

1. Open the channel's settings, then **Edit name and topic**.
2. Change either, then tap **Save**.

**Expected result:**

- The header and the channel list show the new name and topic, for every member, without a reload.

---

### JN-CHAT-011: Leave a channel

**Preconditions:** You were added to a channel yourself, not only through a group, and it isn't `general`.

**Steps:**

1. Open the channel's settings, then **Leave channel**.
2. Tap **Leave**.

**Expected result:**

- The app goes to `general`, and the channel is gone from your list.
- The members who stay see "<you> left the channel", then a new key.

**Notes:**

- `general` has no **Leave channel**, and neither does a channel you are in only through a group.
- The last owner can't leave; the Quark says to make someone else an owner first.

---

### JN-CHAT-012: Delete a channel

**Preconditions:** You own a channel other than `general`, or are an admin.

**Steps:**

1. Open the channel's settings, then **Delete channel**.
2. Type the channel's name, then tap **Delete**.

**Expected result:**

- **Delete** stays off until the name is typed exactly.
- The app goes to `general`, and the channel, its messages and its keys are gone for everyone.

**Notes:**

- `general` has no **Delete channel**, and its `everyone` row is shown in **Members** but can't be removed.

---

### JN-CHAT-013: An admin manages a channel they are not in

**Preconditions:** Signed in as an admin. Someone else owns a private channel the admin isn't in.

**Steps:**

1. Open the chat page's channel list.
2. Under **Other channels**, open the channel.

**Expected result:**

- The header, settings and members show, but no messages: the composer reads "You aren't in this channel. As an admin you can manage it, but not read it."
- Settings offer **Edit name and topic**, **Members** and **Delete channel**.

