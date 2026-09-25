# Chat security

Chat messages are end-to-end encrypted: only the members of a channel can read them, and the Quark stores
ciphertext it can't open. This page covers the identity keys that make that possible (#2416) and what they
protect against, then the channel keys and key grants built on them (#2417), then the messages encrypted under
those keys (#2418).

## Identity keys

Each account has a chat identity, generated in the app, never on the Quark:

- an **X25519** keypair. Channel keys are sealed to it (`crypto_box_seal`) so only this account can open them.
- an **Ed25519** keypair. It signs key grants and channel events, so a grant the Quark forged is rejected.

The private halves come from two random 32-byte seeds. Those 64 bytes leave the device only encrypted, and they
are encrypted twice:

1. under a key derived from the **login password**
2. under a key derived from the **recovery phrase**. Every account gets one at first sign-in, and recovery is
   the only way to reset a password, so this wrap is what keeps chat history through a recovery.

Each wrap is XChaCha20-Poly1305 under `Argon2id(secret, salt)`, with a fresh random 16-byte salt and a random
24-byte nonce. All of it runs on libsodium in the app, through the `sodium` package: native libsodium on phones
and desktop, and `web/sodium.js` (the sumo build, since Argon2id needs it) in the browser.

The Quark stores one `user_chat_keys` row per account: the two public keys, the two wraps and their salts, and
`kdf_params`, the Argon2id cost in the client's own JSON. That's ciphertext and public keys only.

### Argon2id cost

New wraps use 3 passes over 64 MiB (`KdfParams.standard` in `lib/models/chat_keys.dart`). With the shipped
sodium.js in Chrome on an Apple M2 Pro:

| Passes | Memory  | Time   |
| ------ | ------- | ------ |
| 2      | 64 MiB  | 68 ms  |
| 3      | 64 MiB  | 100 ms |
| 3      | 128 MiB | 220 ms |
| 3      | 256 MiB | 456 ms |

A mid-range phone's browser is several times slower than that, so 64 MiB keeps an unlock under the one-second
budget with room to spare, and it doesn't ask a phone's browser for a large WebAssembly allocation. The cost is
stored with each wrap, so it can go up later without breaking existing ones.

### Lifecycle

| When                          | What the app does                                                                     |
| ----------------------------- | ------------------------------------------------------------------------------------- |
| First sign-in or setup        | Generates the identity, wraps it under the password and the phrase it just showed, and uploads it |
| Sign-in, no keys yet          | An account from before chat: generates and uploads, wrapped under the password only    |
| Sign-in                       | Downloads the wraps and opens the password one with the password from the form        |
| Recovery                      | Fetches the wraps with the phrase, opens the phrase one, and sends both re-wrapped in the same request that resets the password |
| Restart on a phone or desktop | Reads the unwrapped seeds back from the platform keystore (`flutter_secure_storage`)  |
| Reload on the web             | Nothing is kept, so chat asks for the password again before it can read               |
| Sign-out                      | Forgets the identity and deletes the cached seeds                                    |
| Account deleted               | The Quark deletes the row                                                            |

Keys made at a later sign-in have no phrase wrap, because the phrase is only ever shown once. That covers accounts
from before chat, and accounts someone requested (#1908), whose phrase is shown at the request, before there is a
session to upload keys with. If such an account is recovered, nothing can open its old identity, so recovery makes
a new one and its earlier messages stay sealed. Accounts from setup and accounts an admin created get their keys
while the phrase is on screen, and don't have this problem.

### Routes

- `GET /api/v0/chat/keys/me`: the caller's row, wraps included, or 404 before it has one.
- `PUT /api/v0/chat/keys/me`: create or replace it. The Quark checks sizes and caps the body at 8 KiB.
- `GET /api/v0/chat/keys/:userId`: an active account's two public keys, to any signed-in account. Never a wrap.
- `POST /api/v0/auth/recover/keys`: no session, rate-limited like sign-in. Checks the recovery phrase and
  returns the wraps, so the app can open them before it resets the password.
- `POST /api/v0/auth/recover` takes an optional `chatKeys` with the re-wrapped row and stores it in the password
  reset's transaction.

## Channel keys

Each channel has a symmetric XChaCha20-Poly1305 key with a version number. A member holds a version through a
**key grant**: the key sealed to their X25519 key (`crypto_box_seal`, 80 bytes) and signed with the Ed25519 key of
the member who granted it. Clients make keys and grants; the Quark stores them and can open neither.

### What a signature covers

A grant's signature covers these bytes, so it can't be replayed to another account, version or channel:

```text
"quark-chat-grant-v1" 0x00 || be64(channelId) || be64(version) || be64(recipientUserId) || BLAKE2b-256(sealedKey)
```

The Quark copies the granter's published signing key into the grant when it's uploaded (`granterSignKey`), and the
recipient verifies against that. A grant from an account that was later deleted, or that recovered with a new
identity, still verifies. Trusting that copy is no weaker than trusting `GET /chat/keys/:userId`, since the Quark
serves both; closing that gap is #2430 (see below). A grant whose signature fails is dropped, and the channel stays
waiting.

### Distribution

- **Who is pending.** The Quark resolves the channel's members (direct, through a group, or through `everyone`) and
  lists each one who has published chat keys but lacks a version. New members are pending for **every** version,
  so they can read the history.
- **Telling holders.** A watcher on the Quark reruns that check on every `access_changed` (a group gained or lost an
  account), `account_changed` (an account was created, approved, turned off or deleted) and `chat_channel_changed`.
  It also runs when an account publishes or replaces its keys. For each channel with pending grants it publishes
  `chat_key_needed` to the members who hold a version. Any of them that is online seals the key to each pending
  member, signs, and uploads. The first grant for a member and version wins, and later ones are ignored.
  `chat_key_granted` then tells the recipients.
- **Waiting.** Until its grant lands, a member sees "Waiting for a member to share the key". The Quark can't end
  that wait itself.
- **The first key.** A channel starts with no version. The first member client to open it, `general` on a new
  Quark included, creates version 1. Creating a version must name the next number, so two clients racing leave
  one winner.
- **A new identity.** When an account uploads a different X25519 key, its grants are deleted, since nothing can
  open them now. It becomes pending again and members refill them, history included.

### Rotation

The key needs rotating when anyone outside the channel holds the current version: a member removed or who left,
someone who left a group on the channel, a turned-off account, or a deleted one. A grant to a deleted account is
kept with no recipient for this purpose. The Quark reports `rotationNeeded` and sends `chat_key_needed`, and the
next member client online creates the next version and grants it to the remaining members. That member doesn't
have to hold the old version. Messages from then on use the new key.

### Channel events

Membership changes and new key versions are stored in `chat_channel_events`. Each row has a kind (`member_set`,
`member_removed`, `key_created`), the actor, and a JSON payload the Quark builds. The actor's client then signs:

```text
"quark-chat-event-v1" 0x00 || be64(channelId) || be64(eventId) || be64(actorId) || kind 0x00 || payload
```

The client signs only an event whose payload matches what it just did. An event nobody signed is shown as
unverified. That covers an admin who adds themselves to a channel without signing, and anything the Quark made up.
Storing a signature sends the members `chat_channel_changed`, so an event they are showing as unverified turns
verified without the channel being reopened.

### What the Quark sees

- Which versions of which channel's key exist, who created each one, and when.
- Who holds each version, who granted it to them, and when. The sealed keys and signatures are opaque to it.
- The membership and key events in plain text.

It can refuse to store a grant, drop one, or serve a stale list. It can't hand a member a key of its own without
the signature check catching it, unless it also lies about the granter's public key (#2430).

### Routes

All are members only: anyone else gets 404, admins included.

- `GET /api/v0/chat/channels/:id/keys` returns the versions, the current one, the caller's own grants, and
  `rotationNeeded`.
- `POST /api/v0/chat/channels/:id/keys` creates the next version with the caller's own grant.
- `GET /api/v0/chat/channels/:id/keys/pending` returns the grants the caller can fill.
- `POST /api/v0/chat/channels/:id/keys/grants` uploads grants for versions the caller holds.
- `GET /api/v0/chat/channels/:id/events` returns the channel's events.
- `PUT /api/v0/chat/channels/:id/events/:eventId/signature` lets the actor sign an event, once.

## Messages

A message is encrypted on the sender's device under the channel's current key version, and only ciphertext
reaches the Quark (#2418). It is XChaCha20-Poly1305 with a random 24-byte nonce, stored as `nonce || ciphertext`,
and at most 16 KiB. Larger bodies are refused with 413, and files are shared separately (#2425).

### What the additional data binds

Each message is encrypted with this additional data:

```text
"quark-chat-msg-v1" 0x00 || be64(channelId) || be64(keyVersion)
```

The reader rebuilds it from the channel it is reading and the `keyVersion` the Quark reports. So a ciphertext
the Quark copies into another channel, or relabels with another key version, fails to decrypt, and the app shows
it as unreadable rather than as a message. The message id and author aren't bound: the Quark assigns the id after
encryption, and binding the author would make a deleted account's history unreadable once its `authorId` is
cleared.

The additional data doesn't stop the Quark replaying a ciphertext within the same channel and version, reordering
messages, or claiming a different author. Any member holding the key could also write a message that looks like
it came from someone else, since the key is shared. Per-message signatures would close both gaps, and are left
for later.

### What the Quark sees

- Who posted in which channel, when, under which key version, and how long the ciphertext is.
- Deletions. A deleted message keeps its row as a tombstone: the ciphertext is wiped and `deleted_at` is set.

### Delivery

- **Live.** `chat_message_created` carries the whole stored row, and `chat_message_deleted` carries the id and
  channel. Both go to the channel's members over the existing `/api/v0/events` socket, and **only** to them. An
  admin who isn't a member hears neither, unlike every other event.
- **Catch-up.** The socket drops events when a client falls behind, and it has no replay. So the app never
  trusts it alone: when a channel opens, and on every reconnect, it fetches `?after=` the newest id it holds.
- **Waiting.** A message under a key version this account has no grant for yet is shown as waiting. It opens by
  itself once a member shares that version.
- **Plaintext** is held in memory only, and is dropped when the channel is closed or chat locks.

### Routes

All are for members only: anyone else gets 404, admins included.

- `POST /api/v0/chat/channels/:id/messages` takes `{ciphertext, keyVersion}` and needs `write`. A `read` member
  gets 403.
- `GET /api/v0/chat/channels/:id/messages?before=<id>&limit=50` pages backward, and `?after=<id>` pages forward.
- `DELETE /api/v0/chat/messages/:id` is allowed for the author or a channel owner.

## Threat model

### What this protects against

- **Someone with the disk or a backup.** Messages and channel keys are ciphertext, and the identity keys are
  wrapped under secrets the disk doesn't hold.
- **Another admin reading the database.** Being an admin, or adding yourself to a channel, gives you no key to
  what was said before. Joining shows up to the members as an event, unverified unless the admin's client signed it.
- **The Quark process reading history at rest.** The server never decrypts anything; it stores and forwards
  bytes.

### What it doesn't protect against

- **A malicious running Quark, in phase 1.** The login form sends the password to the Quark, and the password is
  what derives the wrapping key. A compromised server could record it at sign-in, fetch the wrap, and open the
  identity. It could also hand out a public key of its own in place of a member's. Closing this gap means
  the login stops sending the password itself; that's #2430. Until then, chat is a beta, and this is the reason.
- **Metadata.** The Quark sees who is in which channel, when each message was sent, and how big it is.
- **A device that's already unlocked.** On phones and desktop the unwrapped seeds sit in the platform keystore
  while signed in, so anyone who can use the signed-in app can read chat.
- **A removed member's copies.** Removal rotates the channel key for future messages, but nothing takes back what
  a member already downloaded. The Quark also stops serving them grants and ciphertext.
