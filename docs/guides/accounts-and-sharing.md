# Accounts and sharing

How people share one Quark: who can do what, where files live, how to give someone access, and how sign-in
sessions work. It describes what Quark does today. Anything it does not do yet says so and names the issue.

Each behavior below has a numbered journey in [`docs/user-journeys/`](../user-journeys/README.md), cited as
`JN-XXX-NNN`, if you want the exact steps.

## Members and admins

Every account is one of two kinds.

| | Member | Admin |
| --- | --- | --- |
| Sign in, use Files, Photos, Chat and the rest | Yes | Yes |
| Own home folder (`users/<name>`) | Yes | Yes |
| Share their own files and folders | Yes | Yes |
| See the **Users** page and **Vault** in the drawer | No | Yes |
| Add, turn off, delete accounts; approve account requests | No | Yes |
| Make or remove admins; manage groups | No | Yes |
| Browse every folder, including other people's homes (**All files**) | No | Yes |
| Manage sharing on anything, not only their own | No | Yes |
| Reset this Quark | No | Yes |

A member who opens `/users` directly lands back in Files, and the Quark refuses account requests from a member
either way (JN-USR-002).

The first account, made during setup, is an admin. A Quark always keeps at least one admin: the last admin has no
actions menu on the Users page, and removing or deleting the last admin is refused with "This Quark needs at
least one admin. Make someone else an admin first." (JN-USR-005, JN-AUTH-015).

### What an admin does with accounts

On **Users** > **Accounts**, the actions menu on a row offers:

- **Make admin** / **Remove admin**: takes effect at once, with no sign-out needed (JN-USR-003, JN-USR-004).
- **Disable** / **Enable**: a disabled account is signed out everywhere and cannot sign in, but its files and
  shares stay as they were. Enabling brings it all back (JN-USR-011, JN-USR-012).
- **Delete**: the account can no longer sign in. Its folders stay where they are and the admin who deleted it
  becomes their owner (JN-USR-013).

Your own row has no actions menu. Turning off or deleting your own account happens in Settings (JN-USR-014).

**Delete account** removes only your account and leaves your files and the other accounts. **Reset this Quark**
(admins only) erases every account. Each says how far it reaches before you tap it (JN-ST-026, JN-ST-027).

## Requesting an account

If an admin leaves **Allow account requests** on (the default), the sign-in page shows **Need an account?
Request one**.

1. Choose a username and password and tap **Send request**.
2. Wait. Until an admin approves, signing in says "Your account request hasn't been approved yet."

An admin approves or denies it under **Users** > **Requests**. Approving makes the account and its home folder;
denying frees the username at once (JN-AUTH-009, JN-AUTH-010, JN-USR-008, JN-USR-009).

A username is up to 32 lowercase letters, numbers, dots, dashes or underscores, starting with a letter or number.

Turning **Allow account requests** off hides the option and refuses new requests. Requests already waiting stay
in the list (JN-USR-010, JN-AUTH-012). Admins can also add an account directly with **Add user**, giving the
person an initial password (JN-USR-006).

Not available yet: a history of past requests. The Users page shows only pending ones (tracked in #2482).

## Homes and groups

Files lives in a few places, and the folder explains itself at the top when you open it.

- **Home** (`users/<name>`): your own files, under **My files**. It is private to you unless you share something
  from it. Nobody else sees it, though an admin can reach everything through **All files**.
- **Group folder** (`groups/<Group>`): every member of the group can open it and add to it. A group's folder is
  made with the group.
- **Everyone** (`groups/everyone`): every account is in this group, always. Anything put here is visible to all
  accounts. It cannot be renamed, deleted, or have its members changed.
- **Share**: gives one person (or one group) access to one file or folder, wherever it lives.

Example: the Garcia household has accounts `ana`, `luis` and `kid`. Photos for the whole house go in
`groups/everyone`. Ana and Luis make a group `Parents` and keep the tax folder in `groups/Parents`. Ana's
private notes stay in `users/ana`, and when she wants Luis to see one folder, she shares just that folder with him.

Things to know:

- You only see group folders for groups you belong to, plus `everyone` (JN-FB-035).
- Homes and group folders can't be moved or deleted by members, though everything inside them is ordinary content
  (JN-FB-037). Deleting a group leaves its folder in place, reachable only by an admin (JN-USR-019).
- The `users` and `groups` folders themselves can't be shared, because access flows down the tree and sharing them
  would hand over every home or every group at once (JN-FB-038).
- Adding someone to a group gives them its shared folders at once; removing them takes those away (JN-USR-018).

### Managing groups (admins)

Under **Users** > **Groups**: **New group**, **Rename**, **Members**, **Delete**. Names are unique ignoring case
and must be a single folder name. Renaming a group renames its folder and keeps what was shared with it
(JN-USR-015 to JN-USR-020). Only accounts that can sign in can be added as members.

## Sharing

Choose **Share...** from the menu on a file or folder you own (or as an admin). In the share sheet pick who, then
a level:

| Level | They can |
| --- | --- |
| **Can view** | Open and download. |
| **Can edit** | View, plus add, rename and delete inside. |
| **Owner** | Edit, plus change who has access, including making other owners. |

You can share with one account, with a group, or with **everyone** (JN-FB-027, JN-FB-028). Change a level or
remove someone from the same sheet (JN-FB-029). Removing or lowering an owner asks first, because an item with
no owner left can only be managed by admins. Only owners and admins see sharing controls (JN-FB-031).

The person you share with sees the item appear without refreshing, and in **Shared with me** ("Shared by ana").
Admins reach everything through **All files** instead (JN-FB-036).

### Inherited access

Access adds up down the tree. If `Family` is shared with `luis` at **Can edit**, everything inside `Family` is
too. In the share sheet for `Family/Recipes`, Luis appears under **Inherited access** ("Can edit · From Family")
with no level menu: change it on `Family`. A subfolder cannot be more private than the folder holding it. Move it
out of `Family` and the inherited access goes away (JN-FB-030).

## Sessions

Signing in creates a session on that device.

- **Where to see them:** Settings > **Account** > **Sessions**. Each shows when it signed in, when it was last
  used, and which one is **This session**.
- **Sign out another device:** tap the sign-out button on its row, or **Sign out everywhere else** to keep only
  this one (JN-ST-029). Whoever was using it has to sign in again.
- **Sign out here:** **Sign out** at the top of the Account tab (JN-ST-022).
- **Expiry:** a session lasts 30 days from its last use, renewing as you use it, and ends for good 90 days after
  it was created even if used every day.
- **Automatic sign-out:** disabling or deleting an account signs it out everywhere.

## Sign-in protection

Quark slows down guessing in two ways.

**Lockout after repeated failures (JN-AUTH-018).** After five wrong passwords for a username from the same
address, the next attempt is refused with a message asking you to wait and try again, even if the password is
right. The first wait is 30 seconds, and each further miss before it ends doubles it, up to 15 minutes. A username
that doesn't exist is locked out the same way, so the lockout never reveals which accounts are real. Twenty misses
from one address lock that address out of every username, and fifty misses on one username from anywhere lock it
out of addresses it has never signed in from, while an address it has signed in from still gets through.
Lockouts are kept in memory only, so restarting the Quark clears them.

**Rate limit.** Sign-in, setup and account requests share a per-address rate limit, and deleting your
account asks for your password under the same limit (JN-ST-026). Too many attempts in a short time get "too many
requests, please slow down" until the limit refills.

Two-factor sign-in is not available yet (#1341).
