# Chat security

Chat messages are end-to-end encrypted: only the members of a channel can read them, and the Quark stores
ciphertext it can't open. This page covers the identity keys that make that possible (#2416) and what they
protect against. Channel keys and key grants are #2417; messages are #2418.

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

## Threat model

### What this protects against

- **Someone with the disk or a backup.** Messages and channel keys are ciphertext, and the identity keys are
  wrapped under secrets the disk doesn't hold.
- **Another admin reading the database.** Being an admin, or adding yourself to a channel, gives you no key to
  what was said before. Joining shows up to the members as a signed event (#2417).
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
- **A removed member's copies.** Removal rotates the channel key for future messages (#2417), but nothing takes
  back what a member already downloaded.
