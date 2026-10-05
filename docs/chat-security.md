# Chat security

Chat messages are end-to-end encrypted: only the members of a channel can read them, and the Quark stores
ciphertext it can't open. This page covers the identity keys that make that possible (#2416) and what they
protect against, then the channel keys and key grants built on them (#2417), then the messages encrypted under
those keys (#2418) and the reactions on them (#2426).

## Identity keys

Each account has a chat identity, generated in the app, never on the Quark:

- an **X25519** keypair. Channel keys are sealed to it (`crypto_box_seal`) so only this account can open them.
- an **Ed25519** keypair. It signs key grants and channel events, so a grant the Quark forged is rejected.

The private halves come from two random 32-byte seeds. Those 64 bytes leave the device only encrypted, and they
are encrypted twice:

1. under a key derived from the **login password**
2. under a key derived from the **recovery phrase**. Recovery is the only way to reset a password, so this wrap is
   what keeps chat history through a recovery.

Each wrap is XChaCha20-Poly1305 with a random 24-byte nonce. All of it runs on libsodium in the app, through the
`sodium` package: native libsodium on phones and desktop, and `web/sodium.js` (the sumo build, since Argon2id needs
it) in the browser.

### Split keys (#2430)

The app never sends the Quark a secret that opens a wrap, apart from the one move of a legacy account to keys (see
[The legacy claim](#what-it-doesnt-protect-against)). Each secret goes through one Argon2id run over the
account's 16-byte auth salt (`GET /api/v0/auth/salt`), and HKDF-SHA256 splits the result into a key the Quark is
sent and a key that wraps the identity and stays on the device:

```text
master       = Argon2id13(password, authSalt)
authKey      = HKDF-SHA256(master, info = "auth")                 sent in the password's place
wrapKey      = HKDF-SHA256(master, info = "chat-wrap")            the password wrap's key

phraseMaster = Argon2id13(normalize(phrase), authSalt)
recoveryKey  = HKDF-SHA256(phraseMaster, info = "recovery-auth")  sent in the phrase's place
phraseKey    = HKDF-SHA256(phraseMaster, info = "recovery-wrap")  the phrase wrap's key
```

`normalize` trims and lowercases, as the Quark always has. The Quark stores only hashes of `authKey` and
`recoveryKey`. `ChatCrypto.deriveAuthKeys` and `deriveRecoveryKeys` in `lib/services/chat_crypto.dart` are the
construction, pinned by fixed test vectors.

The recovery phrase is generated in the app now, not on the Quark: six words from the Quark's own 256-word list
(`lib/utils/recovery_phrase.dart`, checked word for word against `pkg/util/authutil/wordlist.go`), one random
byte per word. So the Quark never sees it, only `recoveryKey`.

`kdf_params.alg` records which scheme each wrap is in:

| `alg`                             | Password wrap               | Phrase wrap                     |
| --------------------------------- | --------------------------- | ------------------------------- |
| `argon2id13`                      | `Argon2id(password, saltPw)` | `Argon2id(phrase, saltRp)`      |
| `argon2id13+hkdf-sha256`          | `wrapKey`, `saltPw` = auth salt | `Argon2id(phrase, saltRp)`  |
| `argon2id13+hkdf-sha256+recovery` | `wrapKey`, `saltPw` = auth salt | `phraseKey`, `saltRp` = auth salt |

In the first two the salt is a fresh random one per wrap, used directly as the key's. Wraps in the older schemes
still open, and move forward as described under Lifecycle.

The Quark stores one `user_chat_keys` row per account: the two public keys, the two wraps and their salts, and
`kdf_params`, the Argon2id cost and scheme in the client's own JSON. That's ciphertext and public keys only.

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
| Setup                         | Generates the phrase and sends only its `recoveryKey`, then generates the identity, wraps it under the password and the phrase it shows, and uploads it |
| Sign-in, no keys yet          | An account from before chat: generates and uploads, wrapped under the password only    |
| Sign-in                       | Downloads the wraps and opens the password one with the password from the form. A first-scheme password wrap is re-wrapped under `wrapKey` |
| Sign-in, no recovery key      | The Quark answers `legacyRecovery: true`, as for an admin-created account's first sign-in: the app opens or makes the identity, generates a phrase, wraps the identity under it, and sends `recoveryKey` and the new row to `PUT /api/v0/auth/recovery-key`. Only after its 204 does it show the phrase |
| Recovery                      | Sends `recoveryKey`, never the phrase, to fetch the wraps and to reset the password; opens the phrase wrap with the phrase's `wrapKey`, or an older one with Argon2id of the phrase, and sends both re-wrapped |
| Recovery, Quark-made phrase   | The Quark answers `legacyRecovery: true`, so the app has to send the phrase, once. Generates a new one, sends its key as `newRecoveryKey` with the reset, wraps the identity under it, and shows it after the reset |
| Restart on a phone or desktop | Reads the unwrapped seeds back from the platform keystore (`flutter_secure_storage`)  |
| Reload on the web             | Nothing is kept, so chat asks for the password again before it can read               |
| Sign-out                      | Forgets the identity and deletes the cached seeds                                    |
| Account deleted               | The Quark deletes the row                                                            |

Keys made at a later sign-in have no phrase wrap, because the app has no phrase to wrap under. That covers accounts
someone requested (#1908) from an app that generates the phrase: it is shown at the request, before there is a
session to upload keys with, and nothing keeps it until the first sign-in. If such an account is recovered, nothing
can open its old identity, so recovery makes a new one and its earlier messages stay sealed. Accounts from setup
get their keys while the phrase is on screen. An account with no recovery key, an admin-created one or one whose
phrase the Quark made before #2430, is given a phrase at its next sign-in, and that adds the phrase wrap it was
missing.

### Routes

- `GET /api/v0/chat/keys/me`: the caller's row, wraps included, or 404 before it has one.
- `PUT /api/v0/chat/keys/me`: create or replace it. The Quark checks sizes and caps the body at 8 KiB.
- `GET /api/v0/chat/keys/:userId`: an active account's two public keys, to any signed-in account. Never a wrap.
- `POST /api/v0/auth/recover/keys`: no session, rate-limited like sign-in. Checks the `recoveryKey`, or for an
  account that has none yet the raw phrase, and returns the wraps, so the app can open them before it resets the
  password.
- `POST /api/v0/auth/recover` takes an optional `chatKeys` with the re-wrapped row and stores it in the password
  reset's transaction.
- `PUT /api/v0/auth/recovery-key`: with a session and the `authKey` re-confirmed, stores a new `recoveryKey`, clears
  the Quark-made phrase, and stores the re-wrapped row in one transaction.

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
serves both. Nothing closes that gap yet: #2430 stopped the Quark learning the secrets that open the wraps, not it
lying about a member's public key (see the threat model). A grant whose signature fails is dropped, and the channel
stays waiting.

The Quark checks the signature too, against the uploader's published signing key and over the same bytes, before it
stores a grant or creates a version, and refuses a bad one with 400 (#2486). That keeps garbage out of the table
and off the event bus. It is defense in depth, not the trust boundary: the recipient's own check is what stops a
Quark that lies about keys.

A grant is first-write-wins, so a member holding the key could get in first with a grant that is signed but sealed
to nothing useful. When the app can't verify or open a grant addressed to it, it deletes it with
`DELETE /chat/channels/:id/keys/grants/:version`, which only the recipient can do for their own grant. The account
is pending again, and the holders hear `chat_key_needed` and refill it. The bad grant's `grantedBy` names who sent it.

### Distribution

- **Who is pending.** The Quark resolves the channel's members (direct, through a group, or through `everyone`),
  keeps those whose effective permissions include `read_messages`, and lists each one who has published chat keys
  but lacks a version. `read_messages` is the only permission that maps to the key: a delegated manager, holding
  `manage_members` or `manage_channel` without it, is never pending and never gets a grant. New members are pending
  for **every** version, so they can read the history.
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

The key needs rotating when anyone without `read_messages` holds the current version: a member removed or who left,
someone who left a group on the channel, a member demoted to a set without `read_messages` (a manage-only set
included), a turned-off account, or a deleted one. Changing any other permission needs no crypto work. A grant to a deleted account is
kept with no recipient for this purpose. The Quark reports `rotationNeeded` and sends `chat_key_needed`, and the
next member client online creates the next version and grants it to the remaining members. That member doesn't
have to hold the old version. Messages from then on use the new key. The Quark refuses any version after the first
unless `rotationNeeded` is true, with 409, so a member can't bury the channel under versions nobody needs (#2485).

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
the signature check catching it, unless it also lies about the granter's public key, which nothing checks yet.

### Routes

All need `read_messages`: anyone else gets 404, delegated managers and admins included.

- `GET /api/v0/chat/channels/:id/keys` returns the versions, the current one, the caller's own grants, and
  `rotationNeeded`.
- `POST /api/v0/chat/channels/:id/keys` creates the next version with the caller's own grant.
- `GET /api/v0/chat/channels/:id/keys/pending` returns the grants the caller can fill.
- `POST /api/v0/chat/channels/:id/keys/grants` uploads grants for versions the caller holds.
- `DELETE /api/v0/chat/channels/:id/keys/grants/:version` deletes the caller's own grant of a version.
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
  channel. Both go to the channel's readers, the members holding `read_messages`, over the existing
  `/api/v0/events` socket, and **only** to them. A delegated manager hears neither, and neither does an admin who
  isn't a reader, unlike every other event.
- **Catch-up.** The socket drops events when a client falls behind, and it has no replay. So the app never
  trusts it alone: when a channel opens, and on every reconnect, it fetches `?after=` the newest id it holds.
- **Waiting.** A message under a key version this account has no grant for yet is shown as waiting. It opens by
  itself once a member shares that version.
- **Plaintext** is held in memory only, and is dropped when the channel is closed or chat locks.

### Routes

All need `read_messages`: anyone else gets 404, delegated managers and admins included.

- `POST /api/v0/chat/channels/:id/messages` takes `{ciphertext, keyVersion}` and needs `send_messages`. A reader
  without it gets 403.
- `GET /api/v0/chat/channels/:id/messages?before=<id>&limit=50` pages backward, and `?after=<id>` pages forward.
- `DELETE /api/v0/chat/messages/:id` is allowed for the author or a holder of `delete_messages`, while they hold
  `read_messages`.

## Reactions

A reaction is encrypted like a message (#2426): XChaCha20-Poly1305 under the channel's current key, a random
nonce, `nonce || ciphertext` on the Quark. So the Quark knows *that* someone reacted, not with what. That is also
why the Quark can't restrict which emoji are allowed, now or later: the app's short list is the only curation.

The plaintext is the emoji in UTF-8, zero-padded to 64 bytes, so every reaction's ciphertext is the same 104
bytes and its length doesn't give the emoji away. The additional data binds it to where it was made:

```text
"quark-chat-reaction-v1" 0x00 || be64(channelId) || be64(keyVersion) || be64(messageId) || be64(userId)
```

So the Quark can't move a reaction to another message or channel, or pin it on another account, without it
failing to open. A reaction is deleted with the account that made it, so its user id is never cleared and can
be bound, unlike a message's author. Like a message, it doesn't stop the Quark dropping or replaying one.

### What the Quark sees

- **Who reacted to which message, and when.** Each reaction is its own row, so the Quark also sees how many
  reactions an account put on a message, and when one was taken back.
- Not which emoji, and not whether two reactions carry the same one.

### Rules

- Adding one needs `add_reactions`, and so does taking back your own. Removing someone else's needs
  `manage_reactions`, which the Moderator and Owner presets carry; like the other message permissions, both need
  `read_messages`, and anyone without it gets 404.
- An account may hold at most 20 reactions on one message, since the Quark can't tell a repeat from a new
  emoji. The app sends each emoji once and taps it again to take it back.
- Deleting a message deletes its reactions in the same statement that tombstones it, and a deleted message takes
  no new ones.

### Delivery

`chat_reaction_changed` carries the stored row when a reaction is added and only its id when it is removed. It
goes to the channel's readers alone, like the message events. There is no separate catch-up route: a page of
messages carries each message's reactions, and on every reconnect the app reads its loaded messages again from
the oldest, which also picks up deletions the socket dropped.

### Routes

- `POST /api/v0/chat/messages/:id/reactions` takes `{ciphertext, keyVersion}`.
- `DELETE /api/v0/chat/reactions/:id` removes one.

## Rate limits

Posting a message, creating a key version, and uploading key grants are each limited per account (#2485), with a
separate bucket per route, so a member can't flood a channel with ciphertext or grant rows. The limit is a burst of
100 and then 10 a second (`ChatWriteRate` and `ChatWriteBurst` in `pkg/util/deputil`), far above what the app
sends: a grant upload carries up to 256 grants, so one burst refills a rotation for thousands of members. Going
over gets 429, which the app shows as "wait a moment and try again". The limits live in memory and reset when the
Quark restarts.

## Threat model

### What this protects against

- **Someone with the disk or a backup.** Messages and channel keys are ciphertext, and the identity keys are
  wrapped under secrets the disk doesn't hold.
- **Another admin reading the database.** Being an admin, or adding yourself to a channel, gives you no key to
  what was said before. Joining shows up to the members as an event, unverified unless the admin's client signed it.
- **The Quark process reading history at rest.** The server never decrypts anything; it stores and forwards
  bytes.

### What it doesn't protect against

- **A malicious running Quark.** Since #2430 the app sends the Quark `authKey` and `recoveryKey`, so recording a
  sign-in, a recovery or a rotation gives a Quark nothing that opens a wrap. The raw password or phrase goes out
  only to move an account the Quark marks `legacy` or `legacyRecovery` to keys, once each. A Quark too old for keys
  is refused before anything goes out, and the Quark refuses a raw password or phrase from an old app with 426. What
  is still open, and why chat is still a beta:
  - **Public keys.** The Quark serves every member's public keys and the granter's signing key, and nothing checks
    them. A Quark that hands out a key of its own in place of a member's can be granted channel keys and read what
    follows. #2430 does not fix this; it needs keys verified out of band.
  - **The web app comes from the Quark.** In a browser, the code doing the crypto is served by the Quark it
    protects against, so a malicious one can serve code that sends the password. Only the native apps are
    outside its reach.
  - **The legacy claim.** The app believes the Quark's `legacy` and `legacyRecovery` answers every time, because it
    cannot tell a Quark that was reset or reinstalled from one that was compromised. So a compromised Quark can
    claim that any account is `legacy` or `legacyRecovery`, on any device and at any time, and get the password at
    that sign-in or the phrase at that recovery, that once. The password opens the password wrap and the phrase the
    phrase wrap. A key the app derived still opens nothing.
  - **48 bits.** A phrase is six words from 256, 48 bits. Argon2id makes each guess cost about 100 ms of a fast
    machine's time, but a Quark holding the phrase wrap can guess offline, without the sign-in rate limit.
- **Metadata.** The Quark sees who is in which channel, when each message was sent, and how big it is, and
  who reacted to which message and when.
  Admins also see the names and topics of private channels they aren't in, through the admin channel list
  (`ListChannels` with `All`); that is by design, for admin tooling (#2488).
- **A device that's already unlocked.** On phones and desktop the unwrapped seeds sit in the platform keystore
  while signed in, so anyone who can use the signed-in app can read chat.
- **A removed member's copies.** Removal rotates the channel key for future messages, but nothing takes back what
  a member already downloaded. The Quark also stops serving them grants and ciphertext.
