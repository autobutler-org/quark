Status: Proposed

<!-- cspell:words generichash outlen unopenable ciphertexts unkeyed -->

# Detecting a Quark that rolls back, swaps or drops vault items

Design for [#3617](https://github.com/autobutler-org/quark/issues/3617). The per-account vault keeps items
confidential from the Quark, but a client cannot tell when the set of items it is served has been changed, and item ids
leak how many items other accounts create. This page lays out the threat, the options for each gap and a
recommendation, and splits the work into tickets. Nothing is built until the owner approves this page or sends it back.
Every decision marked **Owner call** is a security or product tradeoff that this page lays out and does not decide; they
are collected in [Open questions for the owner](#open-questions-for-the-owner).

All references are to `saddle/integration` as of 2026-10-21. Once this is approved and built, the decisions that stand
move into the vault section of `docs/chat-security.md`.

## What is fixed

1. **End-to-end encryption stays as it is.** The vault key is a random 32-byte XChaCha20-Poly1305 key made on the
   client and stored only wrapped (`docs/chat-security.md`, "The vault"). Each item is
   `XChaCha20-Poly1305(vaultKey, nonce, plaintext, ad)` with
   `ad = utf8("quark-vault-item-v1") || 0x00 || formatVersion` (`lib/services/account_crypto.dart:228-292`). The Quark
   stores `ciphertext`, `nonce` and `format_version` per row, and nothing else about an item.
2. **The browser extension keeps working.** [quark-browser-extensions](https://github.com/autobutler-org/quark-browser-extensions)
   reads and writes `/vault/*` with the shapes `internal/server/extension_contract_test.go` pins: `GET /vault/items` is
   a bare JSON array, an item's `id` is a JSON number that the extension puts in the path, and `POST`, `PUT` and
   `DELETE /vault/items[/:id]` answer 201, 200 and 204. Every change below is additive: a new optional field, a new
   route, or a new behavior that a vault only gets once a client that knows about it opts the vault in.
3. **Native autofill decrypts on its own.** `ios/QuarkVaultCrypto` and `org.autobutler.vaultcrypto` open items with no
   Flutter engine, pinned to the Dart by `test/fixtures/vault_vectors.json`
   ([native-autofill-vault.md](native-autofill-vault.md), Decision 1). The ciphertext cache (#3596,
   `lib/controllers/vault_cache_controller.dart`) holds the Quark's own response and is written while the vault is
   locked, so the app has no vault key when it writes it.
4. **Restore keeps item ids.** `vaultRestoreSteps` (`pkg/backup/vault_items_backup.go`) copies each item with its id and
   moves it to the live account's `user_id`, which differs from the backup's on new hardware (#3614). Entries name their
   folder by item id inside the plaintext (`VaultItemData.folderId`, `lib/models/vault_item.dart:9`), so ids cannot be
   renumbered without opening every item.

## How items are keyed today

- `vault_items.id` is `INTEGER PRIMARY KEY AUTOINCREMENT`, one sequence for every account
  (`internal/db/migrations/037_per_account_vault.up.sql:30`). `CreateVaultItem` returns it, and the extension's
  `POST /vault/items` reads it back.
- Every query takes `user_id` beside the id (`sql/queries/vault.sql`), so another account's id reads as not found.
  Isolation holds; only the numbering leaks.
- `ListVaultItems` orders by `id`, "oldest first".
- `vault_changed` carries the `itemId` and reaches only the owner's sessions (`pkg/util/eventbus/eventbus.go:191`).
- `_fetchItems` (`lib/controllers/vault_controller.dart:666-692`) lists everything, skips any item at a
  `formatVersion` other than 1, and skips any item that fails to open, with only a `debugPrint`.

## Threat model

### Who the attacker is

A **malicious or compromised Quark**: the running process, anyone with write access to its database, or an admin who
restores an older backup. "Compromised" includes a Quark whose disk was copied, edited and put back.

### What it can already do, and this page does not change

- **Serve a web app that steals the password.** In a browser the code doing the crypto comes from the Quark it protects
  against (`docs/chat-security.md`, "The web app comes from the Quark"). Everything below protects the native apps and
  the extension, whose code the Quark does not serve. In the web app the same checks run, and catch an honest Quark's
  bugs and a tampered database, but a malicious Quark can serve code that skips them.
- **Deny service.** Refuse requests, delete the vault, serve nothing.
- **Claim an account is `legacy`** and get the password once (`docs/chat-security.md`, "The legacy claim").
- **See metadata.** How many items each account has, their sizes, and when each is written.

### What it can do today that this page closes

Because the additional data binds no item identity and no list is authenticated, it can:

| Attack | What the user sees today | Harm |
| --- | --- | --- |
| **Roll an item back**: serve an older ciphertext of the same item | The old password, notes or TOTP secret, as current | A password the user rotated (perhaps because it leaked) comes back and may be filled; an item the user deleted reappears. |
| **Swap two items' ciphertexts** between ids | Both items, under each other's ids | Entries land in the wrong folder, since `folderId` names an id. An edit to one item overwrites the other's row, so the other is lost. |
| **Drop an item** | Nothing: it is not in the list | The user believes the login is gone, makes a new one, or is locked out of an account. |
| **Duplicate an item** under a second id | The same entry twice | Confusion; an edit to one copy leaves the other stale. |
| **Roll the whole vault back** to an older consistent state | An older vault, as current | All of the above at once. |
| **Read other accounts' activity from ids** | Any account can see the gaps between its own ids | How many items other accounts made, and when. |

What it **cannot** do, and the design leans on: forge an item (it has no key), move an item into another account's
vault (each account's items are sealed under that account's own random vault key, so a foreign ciphertext never opens),
or replace the vault key with one of its own (it cannot wrap a key under `vaultWrapKey` without the password). The
account binding the issue asks for is already there, through the key.

### What is out of scope

- A malicious **client** holding the vault key. It can write anything, including a valid integrity record.
- **Forks across devices** with no shared history. A Quark can show device A one history and device B another. Each
  device can only check what it is shown against what it last saw itself. See [Rollback limits](#rollback-limits).
- Plaintext metadata the Quark needs to store items at all (counts, sizes, times).

## Summary of the proposal

| Gap | Recommendation |
| --- | --- |
| Rollback, swap, drop, duplicate | A **vault manifest**: a list of every live item id with a digest of its stored bytes, plus a counter, MACed under a key derived from the vault key. The Quark stores it opaquely and updates it with compare-and-swap. Clients check every list against it and remember the highest counter they have seen. |
| Atomic writes | A new `POST /vault/commit` that writes items and the new manifest in one transaction, and a new `GET /vault/state` that reads both in one. The old routes stay. |
| Global ids | **Random per-account ids**: the primary key becomes `(user_id, id)`, new ids are random integers below 2^53 that the client may propose, existing ids are kept. |
| Item identity in the additional data | **Not first.** The manifest already detects a swap. Binding the id into the additional data is a format bump that every client must read before any item moves, so it is left as a later, optional step ([Q3](#open-questions-for-the-owner)). |
| Silent skipping | Count items that do not open and say so, in its own small ticket, before anything else. |

Each row is argued below.

## Decision 1: how a client knows the list is the one it wrote

### Options

| Option | For | Against |
| --- | --- | --- |
| A. A per-item version counter bound into each item's additional data | Each item says which version it is. | A version alone detects nothing: the client needs to know which version is current, which is a list. Needs a format bump and re-encryption of every item. Does not catch a drop. |
| **B. A flat manifest**: every live id with a digest of its stored bytes and a vault-wide counter, MACed under a vault-derived key | Catches rollback, swap, drop and duplicate in one check. No change to items, so the extension and native code keep reading them. A vault is small (hundreds to a few thousand items), and clients already fetch every item, so a flat list costs one hash per item. | Every write rewrites the manifest, so writers need compare-and-swap. A client that does not know about it leaves it stale (see [Clients that do not know the manifest](#clients-that-do-not-know-the-manifest)). |
| C. A Merkle root over the items | Lets a client verify one item with a short proof. | Nobody verifies one item alone: the app and the extension list everything, and the autofill cache is a full list. More code in four languages for nothing used. |
| D. A hash chain: each manifest names the previous manifest's digest | A device that saw counter N can check that a later manifest descends from it, which narrows forks. | Checking descent needs every manifest in between, so the Quark must keep the history. Worth revisiting only if fork detection becomes a goal. |

**Recommendation: B.** The issue's "per-item version" is covered by the digest: an older ciphertext of an item has a
different digest from the one the manifest names, so no version number is needed.

### The construction

All of it uses libsodium primitives every client already links: keyed and unkeyed BLAKE2b (`crypto_generichash`), the
same function the autofill key fingerprint uses.

```text
manifestKey = crypto_generichash(outlen = 32, message = utf8("quark-vault-manifest-key-v1"), key = vaultKey)
keyFp       = crypto_generichash(outlen = 16, message = utf8("quark-vault-key-fingerprint-v1"), key = vaultKey)
itemDigest  = crypto_generichash(outlen = 32, message = be64(id) || be32(formatVersion) || nonce || ciphertext)

body = utf8("quark-vault-manifest-v1") || 0x00
    || keyFp                      16 bytes
    || be64(counter)              1 for the first manifest, +1 per commit
    || be64(writtenAtMillis)      the writing client's clock, for copy only
    || be32(n)
    || n × ( be64(id) || itemDigest )   sorted by id, ids unique
mac      = crypto_generichash(outlen = 32, message = body, key = manifestKey)
manifest = body || mac
```

- **Binary, not JSON**, so there is no canonical form to agree on across Dart, Swift, Kotlin and TypeScript.
- **MACed, not signed.** Only holders of the vault key verify, and every holder can also write, so a signature would
  prove nothing a MAC does not. A MAC needs no new key pair to store or wrap.
- **The id is inside the digest**, so a ciphertext served under another id does not match, without touching the item's
  additional data.
- **`keyFp`** ties the manifest to one vault, so a manifest from a deleted vault does not verify against its successor.
- **Plain, not encrypted.** It names ids and counts, which the Quark already knows.

The manifest is a pure function of the stored rows, so it lives in its own Dart file and in the vectors file, and the
Swift, Kotlin and extension code verify it from the same vectors.

### Checking a list

On every list (unlock, reload, `vault_changed`, `resync`), a client holding the vault key:

1. Verifies the MAC and `keyFp`. A bad MAC is tampering.
2. Recomputes each served item's digest and compares the set with the manifest. Items in the manifest that are missing,
   items not in the manifest, and items whose digest differs are each named.
3. Compares `counter` with the **high-water mark** it stored for this account: the highest counter it has verified,
   and that manifest's digest. A lower counter is a rollback; the same counter with a different digest is a fork.
4. Stores the new mark only when every check passed.

The high-water mark is not secret. It needs integrity from the Quark, not from the device, so it goes in local app
storage keyed by host, username and `keyFp`, and is wiped at sign-out with the rest of the account's local state.

### Rollback limits

The page has to say plainly what this does not catch:

- **A device seeing the vault for the first time** (a new phone, a reinstall, cleared storage, a new browser) has no
  mark. It can check that the manifest and items agree, but not that they are the newest. A whole-vault rollback to an
  older consistent state, manifest included, passes on that device. This is trust on first use.
- **A fork** (device A shown one history, device B another) is caught only if one device later sees the other's
  history. Nothing compares devices.
- **A rollback before the first manifest.** A Quark can serve a pre-manifest vault, with no manifest at all, to a
  device that has no mark. A device that has a mark treats a missing manifest as a rollback.
- **The web app** checks, but a malicious Quark serves that code. See the threat model.

**Owner call ([Q5](#open-questions-for-the-owner)):** whether a new device says anything about this.

## Decision 2: atomic writes

Today's routes write one item per request, and the manifest must change with each write. Three shapes:

| Option | For | Against |
| --- | --- | --- |
| A. Write the item, then `PUT /vault/manifest` | No change to item routes. | Two requests. A crash or lost connection between them leaves a valid write that the next check reports as tampering. Two writers race. |
| B. An optional `manifest` field on `POST`, `PUT` and `DELETE /vault/items` | One request per write. | A `DELETE` with a body is unusual and some proxies drop it. A bulk import is still one request per item. A new item's id must be known before the manifest is MACed, which means client-chosen ids (Decision 3). |
| **C. A new `POST /vault/commit`** with any number of puts and deletes and the new manifest | One transaction for one logical change, imports included. Compare-and-swap in one place. The old routes stay exactly as the extension uses them. | A new route for every client to adopt. |

**Recommendation: C**, with a matching read:

```text
GET  /api/v0/vault/state
  200 {"counter": 5, "manifest": "<base64>" | null, "items": [<item as GET /vault/items serves it>, ...]}

POST /api/v0/vault/commit
  {"expectedCounter": 5, "manifest": "<base64>",
   "put": [{"id": 8123..., "ciphertext": "...", "nonce": "...", "formatVersion": 1}, ...],
   "delete": [17, 42]}
  200 {"counter": 6}
  409 {"error": "...", "counter": 7}   the stored counter is not expectedCounter; nothing was written
```

- **One transaction.** `GET /vault/state` reads the counter, the manifest and the items in one read transaction, so an
  honest Quark never serves a manifest that disagrees with its items because a write landed between two requests.
  `POST /vault/commit` checks `expectedCounter` against the stored counter (0 for none), writes every put and delete,
  and stores the manifest and `expectedCounter + 1`, or does none of it.
- **The Quark parses no MAC.** It checks the counter and the shape and bounds of each item as `ValidateItem` does, and
  bounds the body. The counter beside the manifest is a plain copy for the compare-and-swap; clients trust only the one
  inside the MAC.
- **A 409 is ordinary concurrency**: the client re-reads `/vault/state`, re-applies its change to what it finds, and
  commits again. Large imports go in batches, each its own commit.
- **`vault_changed`** is published once per commit, with `itemId` 0 when more than one item changed.
- **Storage.** Two nullable columns on `vault_keys`, `manifest BLOB` and `manifest_counter INTEGER`. They share the
  key row's lifecycle: `DELETE /vault` removes them with the key, and a restore copies them with it.

### Clients that do not know the manifest

An extension or app from before this change writes through the old routes and leaves the manifest stale. A checking
client cannot tell that write from tampering: both look like an item the manifest does not list. There are three ways
through:

| Option | For | Against |
| --- | --- | --- |
| A. The Quark flags the vault "unverified" on any old-route write, and a checking client re-trusts what it sees | Old clients keep writing. | The flag comes from the Quark, so a malicious one sets it whenever it likes, and protection drops to trust on first use at every sync. |
| **B. Once a vault has a manifest, the Quark refuses old-route writes** with 409 and a sentence saying to update the app or extension | After the switch, any disagreement really is tampering or a bug. Reads through the old routes keep working. | An old extension can no longer save a login. It is a behavior change on a route the extension uses, so it waits until the extension that commits has shipped. |
| C. Old-route writes are allowed and checking clients only warn | Nothing breaks. | The warning fires on every write from an old client, and users learn to ignore it. |

**Recommendation: B**, turned on in its own ticket after the extension ships commit support, with A's behavior (a
quiet re-trust) only until then. **Owner call ([Q2](#open-questions-for-the-owner)):** when old-route writes are
refused, and whether an old extension's save failing is acceptable.

## Decision 3: item ids that say nothing about other accounts

| Option | For | Against |
| --- | --- | --- |
| A. A per-account sequence, primary key `(user_id, id)` | Ids stay small. | Still a sequence: the Quark assigns it, so a new item's id is unknown until after it is stored, which rules out one-request commits. |
| **B. Random ids below 2^53, primary key `(user_id, id)`** | Says nothing about any account, its own included. Stays a JSON number the extension already handles; 2^53 is the largest integer JavaScript and Dart on the web hold exactly. A client can propose the id before encrypting, so a commit names new items in its manifest. Per-account keys mean a collision is only ever with the account's own items. | A random id has no order, so "oldest first" moves to `ORDER BY created_at, id`. |
| C. A random string id (UUID) | The usual choice for client-made ids. | The extension parses `id` as a number and puts it in a path. Changing its type breaks the contract; adding a second id field leaves the leaky one in place. |

**Recommendation: B.**

- **Existing ids are kept.** Renumbering would break every `folderId` inside plaintext the Quark cannot open, every
  autofill cache and every manifest. The old numbers have already leaked what they leak; new items stop adding to it.
  **Owner call ([Q10](#open-questions-for-the-owner))** if renumbering through the clients is wanted anyway.
- **`POST /vault/items` takes an optional `id`**, and assigns a random one when it is absent, so the extension's
  creates stop leaking without any change on its side. A proposed id outside `[1, 2^53)` is 400, and one the account
  already uses is 409. Another account's ids cannot collide, so the answer says nothing about them.
- **`POST /vault/commit` puts by id**: an id the account has is replaced, an unknown one is created.
- **The client draws ids** from `randombytes` and retries a 409.

## Decision 4: binding the item id into the additional data

The issue suggests binding the id, account and position into the additional data. With the manifest in place, the
account is already bound by the key, and the id and the item's current version are bound by the manifest's digest.
What binding the id into the additional data adds on top is that a single item opened alone, with no manifest to hand,
still cannot be served under another id. No client opens items alone today.

The cost:

- `ad = utf8("quark-vault-item-v2") || 0x00 || formatVersion || be64(id)`, under a new `formatVersion` 2 with the same
  plaintext layout, because the client chooses which additional data to rebuild from the stored `formatVersion`.
- **Every client must read version 2 before any item moves.** Today's app skips any item not at version 1
  (`vault_controller.dart:677`), and today's extension and native code read only version 1. A migrated item vanishes
  from every client that does not know version 2.
- **A migration that re-encrypts every item**, lazily on the next write or eagerly on unlock, through
  `POST /vault/commit` so the manifest moves with it.

**Recommendation: do not do it in this round.** Revisit if a client ever opens items without the manifest. If the owner
wants it anyway, it lands last, after the extension and the native code read version 2 and a minimum-version gate is
agreed. **Owner call ([Q3](#open-questions-for-the-owner)).**

## The extension

The extension is a separate repository and gets its own issue there. In order:

1. **Nothing changes for it** when random ids land: its creates get random numeric ids it already handles.
2. **It verifies and commits** once `GET /vault/state` and `POST /vault/commit` exist and the manifest vectors are in
   `test/fixtures/vault_vectors.json`. It keeps its own high-water mark in extension storage, which the Quark does not
   serve.
3. **The Quark refuses old-route writes** to manifest-bearing vaults only after that release is out (Decision 2, B).

The contract test gains assertions for the new routes and for `id` being an integer below 2^53. None of its existing
assertions change, apart from the one ticket that turns old-route writes away, which adds a manifest-bearing vault case
beside the existing one rather than editing it.

## Native autofill and its ciphertext cache (#3596)

The cache controller writes while the vault is locked, so it cannot verify anything; it can only carry what the
verifier needs.

- **Cache schema 2** adds `"manifest"` and `"counter"` from `GET /vault/state`, beside the items. The bytes are the
  Quark's, as today.
- **The app writes the high-water mark into the shared container** (the app group on iOS, `noBackupFilesDir` on
  Android) whenever it verifies a list while unlocked.
- **The extension and the autofill service verify** the manifest and digests after the biometric check, and compare
  the counter with that mark. On any failure they fill nothing, which is the autofill design's first failure rule
  ([native-autofill-vault.md](native-autofill-vault.md#failure-ux)), and tell the user to open Quark.
- **A cache with no manifest** (schema 1, or a vault not yet migrated) fills as today until the app has written a mark
  for that vault; after that, a missing manifest fills nothing.

## Restore from backup (#3614)

A restore is a legitimate rollback, and every device that saw a newer counter will notice it. That is correct: the
user must learn that changes made after the backup are gone.

- **The backup carries the manifest.** `vault_items_backup.db` gains the two `vault_keys` columns and
  `VaultItemsBackupVersion` moves to 2. The restore also reads version 1 files, whose vaults come back with no
  manifest. `TestVaultBackupSchema_MatchesLiveTables` keeps the two schemas in step.
- **What a device with a mark sees** after a restore: a valid manifest with a lower counter, or no manifest at all for a
  version-1 backup. The copy can name when the restored manifest was written, from `writtenAtMillis` inside the MAC.
- **Accepting it is the user's decision**, made on each device that notices: the device shows what happened and asks
  before it drops its mark. Accepting a version-1 restore writes a fresh manifest at counter 1 (`expectedCounter` 0).
- **The Quark may say that it restored.** A restore could record its time beside the key. That claim comes from the
  Quark, so a malicious one can make it too; at most it changes the wording, never skips the question.
  **Owner calls ([Q4](#open-questions-for-the-owner), [Q8](#open-questions-for-the-owner)).**

## The vault key changing

A key the device has not seen (a different `keyFp`) is a different vault, not an older one. Start over on any device
does this legitimately. A Quark that kept the wrap of a vault the user deleted could serve it again, and it would open
with the same password. So a device that has a mark for one `keyFp` and is served another tells the user the vault was
replaced, and does not show the other one as if nothing happened.

## Failure UX

Principles for the app tickets. The copy itself goes through `Errors` in `lib/utils/error_text.dart`, and the native
strings follow the same rules.

1. **Do not show changed data as current.** An item that failed its check is marked, and autofill never fills it.
2. **Do not lock people out of their passwords on a suspicion.** The vault is where people keep the way into everything
   else, so a failed check alone does not hide the whole vault. **Owner call ([Q1](#open-questions-for-the-owner)):**
   warn and show, hide what failed, or lock.
3. **Plain words, no mechanism.** No "manifest", "MAC", "rollback", "counter" or "digest". Say what the user would
   notice: "Some of your passwords look older than the last time you opened your vault on this phone."
4. **One next step.** Each state has one action: "Keep this version", "Open Quark", "Update the extension".
5. **Name the likely reason when it is benign, without asserting it.** "If your Quark was restored from a backup taken
   on March 3, that explains it." The Quark's own claim of a restore never replaces the question.
6. **Never accept silently.** The device's mark only moves down when the user chooses to.
7. **Do not alarm by default on what is expected.** A first sync on a new device is not a failure. **Owner calls
   ([Q5](#open-questions-for-the-owner), [Q6](#open-questions-for-the-owner)):** whether a new device says anything,
   and whether copy may say the Quark "may have been tampered with".
8. **Count what does not open.** "2 items couldn't be opened" replaces today's silent skip, with no exception text
   (#1622).

## Migration plan

1. **Schema.** One migration pair per engine (SQLite and PostgreSQL), numbered above `main`'s highest when it lands:
   rebuild `vault_items` with primary key `(user_id, id)` and no `AUTOINCREMENT`, copying every row with its id; add
   `manifest` and `manifest_counter` to `vault_keys`. The down migration restores the single-column key; it can only
   succeed while no two accounts share an id, which it checks and refuses otherwise.
2. **Ids.** Existing items keep theirs. New items get random ones from that release on, through either route.
3. **First manifest.** The first checking client to unlock a vault with no manifest builds one from what it is served
   and commits it with `expectedCounter` 0. Before that the vault has nothing to check against, which is the state
   every vault is in today.
4. **Transition.** Until the old-route refusal is on, a checking client that finds the manifest stale re-trusts what it
   sees and commits a new manifest, as Decision 2, A describes. Protection is real only once the refusal is on, and the
   docs say so.
5. **Backups.** Version 2 backup files carry the manifest; version 1 files still restore, with none.
6. **Additional data version 2**, only if [Q3](#open-questions-for-the-owner) says so, after every client reads it.

## Test plan

- **Vectors.** `test/fixtures/vault_vectors.json` gains manifest cases: a valid manifest for a fixed key and item set,
  and one rejection each for a bad MAC, a wrong `keyFp`, an unsorted or duplicated id, a missing item, an extra item, a
  rolled-back item and a swapped pair. `test/services/vault_vectors_test.dart` computes them from the Dart; the Swift,
  Kotlin and extension suites check the same file.
- **Dart unit tests** for the checker: each attack in the threat model table, a lower counter, the same counter with a
  different digest, a missing manifest with and without a mark, a changed `keyFp`, and a first sync with no mark.
- **Controller tests** with fake services: a 409 on commit re-reads and retries; a commit that fails leaves the local
  items and mark as they were; accepting a restore writes a manifest; unopenable items are counted.
- **Go unit tests** (`pkg/util/vaultutil`): compare-and-swap (stale counter is 409 and writes nothing), a commit that
  fails part way writes nothing, random ids are in range and retried on collision, a proposed id the account already
  has is 409, two accounts may hold the same id.
- **Integration tests** (`internal/server/api/v0/vault`): the new routes' shapes and statuses, account isolation for
  both, `vault_changed` once per commit.
- **Extension contract test**: every existing assertion unchanged, plus `id` below 2^53, and (in the refusal ticket) a
  manifest-bearing vault answering an old-route write with 409.
- **Migrations**: up and down on SQLite and PostgreSQL keep every id and row; `make check/migrations`.
- **Backup**: a version 2 round trip keeps the manifest; a version 1 file restores with none; the schema test.
- **Native**: the Swift and Kotlin suites verify the manifest vectors; the fill path fills nothing on each rejection.

## Tickets, in landing order

Each is one reviewable PR. Paths are disjoint except where a ticket is blocked by the one before it on the same file,
which the blocked-by link already serializes; those shared files are named.

1. **docs: document rollback, swap, omission and id leakage in the vault threat model.** `docs/chat-security.md` (the
   vault section and "What it doesn't protect against"). States today's limits honestly, before any fix.
   **Difficulty: mechanical (the text is this page's threat model section).**
2. **fix: count vault items that don't open instead of skipping them silently.** `lib/controllers/vault_controller.dart`
   (`_fetchItems`), `lib/widgets/vault/vault_unopenable_notice.dart` (new), `lib/utils/error_text.dart`,
   `test/controllers/vault_controller_test.dart`. Needs no owner call.
   **Difficulty: standard (a scoped controller and UI change).**
3. **feat: vault manifest construction and test vectors.** `lib/services/vault_manifest.dart` (new),
   `test/services/vault_manifest_test.dart` (new), `test/fixtures/vault_vectors.json`,
   `test/services/vault_vectors_test.dart`. Pure code, parallel with 2 and 4. Blocked by approval of the construction.
   **Difficulty: hard (a permanent cryptographic format).**
4. **feat: random per-account vault item ids and manifest storage.** Migration pairs in `internal/db/migrations/` and
   `internal/db/migrations_postgres/`, `sql/queries/vault.sql`, regenerated `internal/db/` and `internal/db/pgdb/`,
   `pkg/util/vaultutil/` (random ids, optional proposed id, the commit and state services),
   `internal/db/vault_items_backup_schema.go`, `pkg/backup/vault_items_backup*.go` (backup version 2, reads 1).
   **Difficulty: hard (a primary-key rebuild on two engines and a backup format bump).**
5. **feat: GET /vault/state and POST /vault/commit, and an optional id on item create.**
   `internal/server/api/v0/vault/`, `docs/swagger/`, `internal/server/extension_contract_test.go` (additive
   assertions only). Blocked by 4. **Difficulty: standard (handlers over services ticket 4 adds).**
6. **feat: write and check the vault manifest in the app.** `lib/services/vault_service.dart`,
   `lib/controllers/vault_controller.dart` (shared with 2, blocked by it), `lib/services/vault_high_water.dart` (new),
   `lib/widgets/vault/vault_integrity_banner.dart` (new), `lib/utils/error_text.dart` (shared with 2),
   `test/controllers/vault_controller_test.dart` (shared with 2). Blocked by 2, 3, 5 and answers to Q1, Q4 to Q6.
   **Difficulty: hard (failure handling and copy for a security check).**
7. **feat (quark-browser-extensions): verify and commit the vault manifest.** That repository only. Blocked by 3 and 5.
   **Difficulty: standard (ports ticket 6's logic against the shared vectors).**
8. **feat: carry the manifest to native autofill and check it before filling.** `lib/services/vault_cache.dart`,
   `lib/controllers/vault_cache_controller.dart`, `ios/QuarkVaultCrypto/`, `android/app/src/main/kotlin/org/autobutler/vaultcrypto/`
   package and their tests. Blocked by 3, 5 and 6 (the mark it writes).
   **Difficulty: hard (three languages agreeing on a security check).**
9. **feat: refuse old-route item writes to a vault that has a manifest.** `pkg/util/vaultutil/vaultutil.go`,
   `internal/server/api/v0/vault/create_vault_item.go`, `update_vault_item.go`, `delete_vault_item.go`,
   `internal/server/extension_contract_test.go`. Blocked by 7's release and Q2.
   **Difficulty: standard (a guarded behavior change on three routes).**
10. **feat: bind the item id into the vault item's additional data (version 2).** Only if Q3 says so.
    `lib/services/account_crypto.dart`, `lib/models/vault_item.dart`, the vectors, the native crypto, and the
    extension. Blocked by every client reading version 2. **Difficulty: hard (a format bump across four clients).**
11. **docs: move the vault integrity decisions into the architecture docs and journeys.** `docs/chat-security.md`,
    `docs/user-journeys/vault.md`, and this page's status. Last.
    **Difficulty: mechanical (records what landed).**

## Open questions for the owner

These are security or product calls. The page recommends where it can and leaves the decision here.

1. **What a failed check does.** Show everything with a warning and mark what failed (recommended, with autofill
   refusing marked items), hide the items that failed, or lock the vault until the user acts. Hiding and locking trade
   availability for safety, for users who keep the way into everything else here.
2. **When old-route writes are refused.** Recommended: after the extension release that commits, with an old
   extension's save then answered by "update the extension". Until then protection is trust on first use at each stale
   sync. Is breaking an old extension's save acceptable, and after how long?
3. **Additional data version 2.** Is binding the id into each item's additional data worth a format bump and a
   re-encryption of every vault, given the manifest already detects a swap? If yes, what minimum app, extension and
   native versions gate the migration?
4. **Accepting a restore.** Should each device that notices a restore ask the user before accepting it (recommended),
   and should accepting ask for the password again?
5. **A new device.** Say nothing on a first sync (recommended), add a quiet line in the vault's details, or show a
   notice that this device cannot yet tell whether it is seeing the newest vault?
6. **How strongly to word it.** May copy say the Quark "may have been tampered with", or only describe what looks
   different? The users are mostly non-technical, and an alarm that a restore also triggers will be learned and
   ignored.
7. **The web app.** Run the checks there too (recommended: they catch bugs and database edits), and say anywhere that
   in a browser they do not hold against a malicious Quark?
8. **The Quark's restore claim.** May a Quark-reported "restored on <date>" change the wording, given a malicious Quark
   can send it?
9. **Forks.** Accept that a Quark can show two devices different histories undetected, or add a way to compare (for
   example, a short code from the manifest that two devices can show side by side)?
10. **Existing ids.** Keep them (recommended), or renumber every vault through its clients so old ids stop telling
    anything?
