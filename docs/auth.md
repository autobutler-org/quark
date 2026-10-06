# Authentication

Quark uses local username/password auth. No cloud, no OAuth required — your credentials live on your device.

The client derives a 32-byte **auth key** from the password and a 32-byte **recovery key** from the phrase, and
sends those in their place (#2430). An account made before auth keys, a **legacy** account, hands the Quark its raw
password once, beside its new auth key, at its next sign-in, and its raw phrase once, beside both new keys, if it
recovers before it has a recovery key; each moves the account to keys and clears the raw secret's hash. Every other
body carrying a raw `password`, `newPassword` or `recoveryPhrase` is what only an app from before auth keys sends,
and gets **426** with an `error` telling the user to update the app. Some curl examples below cannot be typed by hand
for that reason: the key has to be derived first, and the planned `quark auth-key` command (#2713) is what will do it
from a shell.

The examples below use `http://localhost:8080`, which is what `make watch/backend` (or `make serve/backend`)
serves. If you're running the secure mode instead, the base URL is `https://localhost` and `curl` needs `-k`,
because the certificate is self-signed.

## Deriving the keys

Ask for the account's salt first; this needs no session:

```bash
curl 'http://localhost:8080/api/v0/auth/salt?username=you'
```

```json
{ "salt": "3q2+7wAAAAAAAAAAAAAAAA==", "legacy": false, "legacyRecovery": false }
```

`salt` is the standard base64 of 16 bytes. A username with no account gets a salt too, the same one every time, so
the answer does not say whether the account exists. Then:

```text
master  = Argon2id13(secret, salt, t=3, m=64 MiB, p=1), 32 bytes
authKey = HKDF-SHA256(ikm = master, salt = none, info = "auth"), 32 bytes             (secret = password)
recoveryKey = HKDF-SHA256(ikm = master, salt = none, info = "recovery-auth"), 32 bytes (secret = phrase, lowercased and trimmed)
```

Each key is sent as the standard base64 of its 32 bytes; anything else is a 400. `ChatCrypto` in the app is the
reference implementation.

The Quark stores each key as `sha256:` and the hex SHA-256 of that base64 string, and compares in constant time
(#2765). Argon2id is the slow, memory-hard step in front of every password guess, so a second slow hash on the Quark
bought nothing and cost a core-second per HTTP Basic request. Only a value shaped like a key takes the fast hash. The
password and phrase hashes of a legacy account stay bcrypt until the account moves to keys. An auth key stored with
bcrypt before this change is verified with bcrypt once more, and that first correct key rewrites its row to SHA-256;
a build from before the change cannot verify a rewritten row.

`legacy` is `true` for an account that has no auth key yet: it never signed in with an app that sends one, and the
app upgrades it at the next sign-in (see [Logging in](#logging-in)). `legacyRecovery` is `true` for an account with no
recovery key, which the app gives one at sign-in or at a recovery (see [Recovery keys](#recovery-keys)). An unknown
username reads `false` for both.

## First boot

When you start Quark for the first time, there are no users. Everything is wide open until you run setup — so do that first.

```bash
curl -X POST http://localhost:8080/api/v0/auth/setup \
  -H "Content-Type: application/json" \
  -d '{"username": "you", "authKey": "<auth key>", "recoveryKey": "<recovery key>"}'
```

The app does this for you: it generates the recovery phrase, shows it to you once, and sends only the two keys. You
get back a session token. Write the phrase down somewhere safe: it's the only way to reset your password if you
forget it.

## Logging in

```bash
curl -X POST http://localhost:8080/api/v0/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username": "you", "authKey": "<auth key>"}'
```

Returns a session token and `legacyRecovery`. Sessions last 30 days. A wrong key, or an account that has no auth key,
answers 401.

A legacy account signs in once with both credentials:

```bash
curl -X POST http://localhost:8080/api/v0/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username": "you", "password": "<password>", "authKey": "<auth key>"}'
```

The password is checked against the stored hash, and on success the auth key, the salt `/auth/salt` returned and a
cleared password hash land in one write, so the password never signs in again and the next sign-in sends only the
key. If that write fails the sign-in is refused with 500 and the account stays as it was. An account that already has
an auth key is checked by the key, and a password beside it is ignored. The password with no `authKey` is a 426.

`/auth/request-account` takes the same `authKey` and `recoveryKey` as setup, and `POST /admin/users` takes `authKey`
for the account it adds. Wherever an action asks for the password again, or a request uses HTTP Basic, the client
sends the auth key as the password; a raw password there is a 426 too. HTTP Basic sits behind the same lockout as
`/auth/login`: wrong keys count toward it, and a locked-out request gets 429 with `Retry-After`, whatever key it sends.

## Using the token

Pass it as a Bearer token:

```bash
curl http://localhost:8080/api/v0/some-endpoint \
  -H "Authorization: Bearer <your-token>"
```

Or it gets set automatically as a cookie if you're going through the browser.

## Logging out

```bash
curl -X POST http://localhost:8080/api/v0/auth/logout \
  -H "Authorization: Bearer <your-token>"
```

This kills the session server-side. The cookie gets cleared too.

## Forgot your password?

Use your recovery phrase. The app derives its recovery key and the new password's auth key with the account's salt:

```bash
curl -X POST http://localhost:8080/api/v0/auth/recover \
  -H "Content-Type: application/json" \
  -d '{"username": "you", "recoveryKey": "<recovery key>", "newAuthKey": "<new auth key>"}'
```

This replaces the auth key, clears any password hash, invalidates all existing sessions, and gives you a fresh token.
Your recovery phrase stays the same. `/auth/recover/keys` takes the same `recoveryKey` and returns the chat keys to
re-wrap first. A wrong key, an unknown username and an account with no recovery key all get the same 400.

An account with `legacyRecovery: true` and a phrase the Quark once made recovers with that phrase once:

```bash
curl -X POST http://localhost:8080/api/v0/auth/recover \
  -H "Content-Type: application/json" \
  -d '{"username": "you", "recoveryPhrase": "<phrase>", "newAuthKey": "<new auth key>", "newRecoveryKey": "<new phrase'"'"'s key>"}'
```

The phrase is checked against the stored hash, and the reset stores both new keys and clears the phrase and password
hashes, so the app shows the new phrase it generated. `/auth/recover/keys` takes the raw `recoveryPhrase` the same way,
for an account that has no recovery key. An account that has one refuses every raw phrase as a wrong phrase. A
`recoveryPhrase` without both new keys, or a `newPassword`, is a 426.

### Recovery keys

- **New accounts.** `/auth/setup` and `/auth/request-account` take `recoveryKey` beside `authKey`. The Quark never
  makes a phrase. An account made without one, and every account an admin adds, has no recovery credential until a
  sign-in gives it one.
- **Giving an account a key.** `PUT /api/v0/auth/recovery-key` with a session, body `{password, recoveryKey,
  chatKeys?}`, stores the key and answers 204. `password` carries the caller's auth key, so a stolen session cannot
  replace the recovery credential; a wrong or missing one is a 403 and nothing is written. `chatKeys` is the chat
  identity re-wrapped under the new phrase, stored in the same transaction, as `/auth/recover` takes it. The login
  response carries `legacyRecovery: true` for an account with no recovery key, which tells the app to do this.

## Check setup status

```bash
curl http://localhost:8080/api/v0/auth/status
```

Returns `{"setup": true}` or `{"setup": false}`. Useful for the frontend to know whether to show the onboarding flow.

## Notes

- The app asks for a password of at least 8 characters; the Quark only ever sees the key derived from it
- The API is wide open until setup is complete (so finish setup before exposing the port)
- There's no multi-user support yet — one owner account per device
