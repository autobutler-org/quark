# Chat Journeys

Covers the chat beta (#2414): opening a channel, sending and receiving
end-to-end encrypted messages, unlocking chat on web after a reload, waiting
for a channel key, and an admin turning the beta off.

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
