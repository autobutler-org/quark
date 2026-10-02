# Authentication

Quark uses local username/password auth. No cloud, no OAuth required — your credentials live on your device.

The examples below use `http://localhost:8080`, which is what `make watch/backend` (or `make serve/backend`)
serves. If you're running the secure mode instead, the base URL is `https://localhost` and `curl` needs `-k`,
because the certificate is self-signed.

## First boot

When you start Quark for the first time, there are no users. Everything is wide open until you run setup — so do that first.

```bash
curl -X POST http://localhost:8080/api/v0/auth/setup \
  -H "Content-Type: application/json" \
  -d '{"username": "you", "password": "your-password"}'
```

You'll get back a session token and a **recovery phrase**. Write the phrase down somewhere safe. You won't see it again, and it's the only way to reset your password if you forget it.

```json
{
	"token": "abc123...",
	"recoveryPhrase": "wagon-river-flame-orbit-cedar-stone",
	"message": "Setup complete. Store your recovery phrase somewhere safe — it will not be shown again."
}
```

## Logging in

```bash
curl -X POST http://localhost:8080/api/v0/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username": "you", "password": "your-password"}'
```

Returns a session token. Sessions last 30 days.

### Signing in without sending the password

A client does not have to send the password itself. It can derive a 32-byte **auth key** from the password and a
per-account salt, and send that instead. Ask for the salt first; this needs no session:

```bash
curl 'http://localhost:8080/api/v0/auth/salt?username=you'
```

```json
{ "salt": "3q2+7wAAAAAAAAAAAAAAAA==", "legacy": true, "legacyRecovery": true }
```

`salt` is the standard base64 of 16 bytes. A username with no account gets a salt too, the same one every time, so
the answer does not say whether the account exists. `legacy` is `true` for an account that has no auth key yet, and
`legacyRecovery` for one that has no recovery key yet (see [Recovery keys](#recovery-keys)). An unknown username reads
`false` for both.

`POST /api/v0/auth/login` then takes one of three bodies. `authKey` is the standard base64 of exactly 32 bytes;
anything else is a 400.

| Body                            | What it does                                                                        |
| ------------------------------- | ----------------------------------------------------------------------------------- |
| `{username, password}`          | Checks the password, as above.                                                      |
| `{username, authKey}`           | Checks the auth key. An account that has none yet answers 401, like a wrong password. |
| `{username, password, authKey}` | Checks the password and, if the account has no auth key yet, stores this one.       |

The third body is how a `legacy` account is upgraded. The account keeps its password, so a client that still sends
`{username, password}` keeps signing in.

```bash
curl -X POST http://localhost:8080/api/v0/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username": "you", "authKey": "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8="}'
```

`/auth/setup`, `/auth/request-account` and `POST /admin/users` take `authKey` in place of `password`, and
`/auth/recover` takes `newAuthKey` in place of `newPassword`: exactly one of the two, never both. An account made
with an auth key has no password to sign in with. Wherever an action asks for the password again, or a request uses
HTTP Basic, a client that signs in with an auth key sends that key as the password.

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

Use your recovery phrase:

```bash
curl -X POST http://localhost:8080/api/v0/auth/recover \
  -H "Content-Type: application/json" \
  -d '{"username": "you", "recoveryPhrase": "wagon-river-flame-orbit-cedar-stone", "newPassword": "new-password"}'
```

This resets your password, invalidates all existing sessions, and gives you a fresh token. Your recovery phrase stays the same.

A recovery replaces both ways of signing in. `newPassword` clears the account's auth key, which was derived from the
old password; `newAuthKey` clears its password.

### Recovery keys

As with the password, a client does not have to send the recovery phrase. It generates the phrase itself and derives
a 32-byte **recovery key** from the phrase and the account's salt, the same salt `/auth/salt` returns, and the Quark
stores only the key's hash. The client sends the key, as standard base64, wherever a phrase went:
`/auth/recover/keys` and `/auth/recover` take exactly one of `recoveryPhrase` and `recoveryKey`. A wrong key gets the
same 400 as a wrong phrase. Once an account has a recovery key it refuses every raw phrase.

- **New accounts.** `/auth/setup` and `/auth/request-account` take an optional `recoveryKey` beside `authKey` (a 400
  beside `password`). With it the Quark makes no phrase, and the response has no `recoveryPhrase`.
- **Rotation.** `PUT /api/v0/auth/recovery-key` with a session, body `{password, recoveryKey, chatKeys?}`, stores the
  key and clears the old phrase, and answers 204. `password` re-confirms the caller (an auth key client sends its key
  there, as for deleting the account), so a stolen session cannot replace the recovery credential; a wrong or missing
  one is a 403 and nothing is written. `chatKeys` is the chat identity re-wrapped under the new phrase, stored in
  the same transaction, as `/auth/recover` takes it. An account with no auth salt yet is a 409. The login response
  carries `legacyRecovery: true` for an account with no recovery key, which tells the client to rotate; an account an
  admin created rotates the same way after its first sign-in hands it a phrase.
- **A legacy recovery.** An account that never rotated recovers once with its raw `recoveryPhrase`. With
  `newAuthKey`, the same request may carry `newRecoveryKey`, which stores that key and clears the old phrase in the
  recovery's transaction.

## Check setup status

```bash
curl http://localhost:8080/api/v0/auth/status
```

Returns `{"setup": true}` or `{"setup": false}`. Useful for the frontend to know whether to show the onboarding flow.

## Notes

- Passwords must be at least 8 characters
- The API is wide open until setup is complete (so finish setup before exposing the port)
- There's no multi-user support yet — one owner account per device
