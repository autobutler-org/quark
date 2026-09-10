# Competitive analysis: consumer NAS and file managers

What the products a Quark buyer would cross-shop actually do, what we do, and where the gap is.

**Scope.** UGREEN NASync (UGOS Pro), Synology DSM, QNAP QTS, TerraMaster TOS, Asustor ADM, unRAID and
TrueNAS at the enthusiast end, and the two file managers every user already knows — macOS Finder and
Windows File Explorer.

**Method.** The Quark column is grounded in [`docs/user-journeys/`](user-journeys/README.md) and the
handlers under `internal/server/api/v0/`, not in what we intend to ship. Where something exists in the
backend but has no endpoint or no UI, it says so. Competitor claims come from vendor documentation and
product reviews; see [Sources](#sources).

Written for [#1835](https://github.com/autobutler-org/quark/issues/1835). Snapshot as of September 2026 —
this is a point-in-time document, not a living one.

---

## Features we should have

The gaps worth acting on, roughly in order of how much a real buyer would feel them. Each traces to a row
in the comparison below.

1. **More than one user account.** `authutil.Setup` refuses to run once a user exists and nothing else
   calls `CreateUser`, so a Quark holds exactly one account, forever. The `users` table has `is_admin`
   and there are `promote`/`demote` endpoints, but they can only ever act on that one person. A family
   cloud that a family cannot log into is the single biggest gap on this list.
2. **Automatic phone photo backup.** This is *the* reason consumers buy a NAS, and every competitor
   ships it. Quark has manual upload (JN-PH-006) and nothing that runs in the background. No
   `workmanager`, no background upload path anywhere in `lib/`.
3. **Finish the trash.** `storageutil` already implements `TrashFiles`, `ListTrash` and 30-day retention,
   and `fileutil.Delete` routes deletes into `.trash` — but there is no API handler and no UI, so deleted
   files sit in a hidden folder the user cannot see, restore, or empty. This is the cheapest item here
   and currently reads as data loss.
4. **Share links.** Send a file or folder to someone without an account, with an expiry and optionally a
   password. Universal across DSM, QTS, UGOS and TOS. Quark has no sharing of any kind — the only way
   data leaves is a download by the one account holder.
5. **SMB (and probably WebDAV).** Every competitor mounts as a network drive in Finder and Explorer.
   Quark is HTTP-only, so it cannot be a drive letter, cannot be opened by a desktop app's file dialog,
   and cannot be a target for any existing backup tool. SMB is the protocol that makes a NAS feel like
   storage instead of a website.
6. **Two-factor authentication on login.** Password plus recovery phrase is all we have. TOTP appears in
   the codebase only as a *field inside vault entries* — we store other people's second factors while
   having none of our own. Adaptive login protection and MFA are DSM baseline.
7. **A desktop sync client.** A folder on the laptop that mirrors to the Quark. Synology Drive, QNAP's
   Qsync, UGREEN's Sync & Backup desktop tools. Without it, Quark is a destination you visit rather than
   a place your files live.
8. **RAID or some redundancy story.** We manage devices and can run a snapshot backup to a second one,
   but there is no array, no parity, no rebuild. "A dead drive doesn't mean dead data" is the core NAS
   promise and we do not currently make it.
9. **Per-folder permissions and quotas.** Follows directly from multi-user — shared folders that some
   accounts can read and others cannot. Not useful before item 1, essential immediately after.
10. **Photo intelligence: faces, objects, places.** We have EXIF, favorites, albums and perceptual-hash
    duplicate detection (`photoutil.DHash`), which is a real start. What's missing is the search that
    makes a 40,000-photo library usable — face grouping and subject tagging, both of which DSM ships.

Two more that are cheap and would close obvious usability gaps against Finder/Explorer rather than
against NAS vendors: **copy/duplicate a file** (we have move and rename, but no copy outside photos) and
**sortable columns** in the file browser.

---

## Feature comparison

Legend: **Yes** shipped · **Partial** exists but incomplete · **No** absent.

### Access and protocols

| Capability | Synology / QNAP / UGREEN / TerraMaster | Finder / Explorer | Quark |
| --- | --- | --- | --- |
| SMB / CIFS network drive | Yes — the default access path | Native client both platforms | **No** |
| NFS | Yes | Finder can mount; Explorer on Pro editions | **No** |
| WebDAV | Yes | Both can mount | **No** |
| FTP / SFTP / rsync target | Yes | — | **No** |
| Browser-based file UI | Yes | — | **Yes** — the primary interface |
| Native mobile apps | Yes (iOS + Android) | — | **Yes** — Flutter, web/iOS/Android |
| Remote access without port-forwarding | Yes — QuickConnect, myQNAPcloud, UGREEN Link | — | **Yes** — Tailscale `tsnet`, no vendor relay |
| iSCSI block storage | Yes on most | — | **No** — and not obviously in scope |

### Accounts and security

| Capability | Competitors | Quark |
| --- | --- | --- |
| Multiple user accounts | Yes, with groups | **No** — one account, hard-capped at setup |
| Per-folder permissions / ACLs | Yes | **No** |
| User quotas | Yes | **No** |
| Two-factor authentication | Yes, MFA and adaptive login protection in DSM 7.2 | **No** — password + recovery phrase only |
| Brute-force auto-block | Yes | **Partial** — `ratelimitutil` exists; no IP banning |
| Session listing and revocation | Varies | **Yes** — plus connected-device revocation (JN-ST-014/015) |
| Encrypted shared folders / volumes | Yes — full volume encryption in DSM 7.2 | **Partial** — the password vault is encrypted; file storage is not |
| Built-in password manager | No — nobody ships this | **Yes** — vault with TOTP fields, folders, import/export |
| HTTPS by default | Yes | **Yes** — self-signed on first boot |

### Files

| Capability | Competitors | Finder / Explorer | Quark |
| --- | --- | --- | --- |
| Browse, upload, download | Yes | Yes | **Yes** — chunked upload sessions, HTTP range downloads |
| New folder, rename, move, delete | Yes | Yes | **Yes** (JN-FB-009 – 013) |
| **Copy / duplicate** | Yes | Yes — `Cmd-D`, Ctrl-C/V | **Partial** — photos only (`photoutil.CopyPhotoVFS`) |
| Trash / recycle bin with restore | Yes | Yes | **Partial** — implemented in `storageutil`, no endpoint, no UI |
| Filename search | Yes | Yes | **Yes** (JN-FB-014) |
| Full-text content search | Yes | Yes — Spotlight / Windows Search | **Yes** — SQLite FTS5 (`searchutil`) |
| File versioning / previous versions | Yes | Time Machine / File History | **No** |
| Browse and extract archives | Yes | Yes | **Yes** (JN-FB-020/021) — including streamed listing |
| Recent files | Yes | Yes | **Yes** (JN-FB-022) |
| Tags / labels | Yes | Finder tags; Explorer partial | **No** |
| Sortable columns | Yes | Yes | **No** |
| Real-time updates across clients | Varies | — | **Yes** — SSE event stream (JN-FB-024) |
| Share links with expiry / password | Yes | — | **No** |
| Public / anonymous upload folder | Yes | — | **No** |

### Photos

| Capability | Synology Photos and peers | Quark |
| --- | --- | --- |
| Automatic mobile backup | Yes — the headline feature | **No** — manual upload only |
| Timeline browsing | Yes | **Partial** — paginated grid, no date scrubber |
| Albums | Yes | **Yes** (JN-PH-010 – 012) |
| Favorites | Yes | **Yes** |
| Face recognition and grouping | Yes | **No** |
| Object / scene detection | Yes | **No** |
| Shared albums / collaboration | Yes | **No** |
| EXIF metadata display | Yes | **Yes** (JN-PH-013) |
| Duplicate detection | Varies | **Yes** — perceptual hashing, better than several competitors |
| Live Photos | Yes | **Yes** — `FindLivePhotoVideo` pairs the motion file |
| Rotate / basic edit | Yes | **Yes** — rotate (JN-PH-014) |

### Data protection

| Capability | Competitors | Quark |
| --- | --- | --- |
| RAID / parity | Yes — the reason the boxes have bays | **No** |
| Snapshots | Yes — Btrfs/ZFS, immutable in DSM 7.2 | **Partial** — snapshot *backup* to a second device (JN-SD-008) |
| Scheduled backup to external / cloud | Yes — Hyper Backup, HBS 3, Sync & Backup | **Partial** — manual job start, no scheduler |
| Cloud-provider sync (Drive, OneDrive) | Yes — UGOS covers seven providers | **No** |
| Disk health / S.M.A.R.T. monitoring | Yes | **Partial** — health dashboard, no per-disk S.M.A.R.T. |
| Ransomware protection | Yes — QNAP Security Center, DSM WORM folders | **No** |

### Platform and apps

| Capability | Competitors | Quark |
| --- | --- | --- |
| Third-party app store | Yes — hundreds on DSM/QTS, ~29 on UGOS | **No** |
| Docker / container manager | Yes, all of them | **No** |
| Virtual machines | Yes on higher tiers | **No** |
| Media server (DLNA / Plex-class) | Yes | **Partial** — in-app video and audio playback only |
| Video transcoding | Yes | **Yes** — `videoutil` via ffmpeg (transcode, trim, frame extract) |
| Document editing | Yes — Synology Office | **Yes** — `.qdoc` editor |
| Spreadsheet editing | Yes | **Yes** — `.qsheet`, plus xlsx conversion |
| Surveillance / camera NVR | Yes — Surveillance Station is a major DSM draw | **No** |
| E-book library | Rare | **Yes** — books listing + epub support |

---

## Where Quark already wins

Worth stating plainly, because the tables above are mostly deficits and that is not the whole picture.

- **Remote access without a vendor in the middle.** QuickConnect, myQNAPcloud and UGREEN Link all relay
  through the vendor's servers. Quark uses Tailscale `tsnet` directly. For a product whose pitch is "off
  servers you don't trust," routing remote access through a vendor relay would undercut the entire
  premise. We don't.
- **No drive lock-in.** Synology spent 2025 restricting its Plus series to certified drives and reversed
  course in DSM 7.3 after sales fell. That reversal left NVMe still restricted and deduplication still
  gated. We have no equivalent and should keep it that way, loudly.
- **A password vault.** No mainstream NAS ships one. It is a genuine differentiator and it is done well —
  encrypted, device-gated, with import/export.
- **One coherent app.** Competitors split functionality across a dozen mobile apps (DS File, DS Photo,
  Synology Drive, Synology Photos…), which is a recurring complaint. Quark is one client for everything.
- **Perceptual-hash duplicate detection**, which several paid competitors don't do at all.
- **No subscription, and the source is open.** Increasingly rare in this category.

---

## Consumer complaints

The gripes matter as much as the feature lists. They mark where shipping a feature is not enough, and
where a competitor's pain is our opening.

### Synology

- **Drive lock-in (2025).** The Plus series was restricted to certified drives; installing a WD Red or
  Seagate IronWolf triggered persistent warnings and disabled features. Synology-branded drives carried
  a steep premium — roughly $299 for an 8TB HAT5310 against ~$220 for an equivalent Seagate Exos. Sales
  fell and the policy was reversed in DSM 7.3 in late 2025, but NVMe stayed HCL-restricted and
  deduplication and firmware updates stayed gated on unverified drives. Reputational damage outlasted
  the reversal.
- **Ageing hardware at premium prices** — repeatedly raised alongside the drive controversy.
- **Feature removal between DSM releases**, which users experience as paying for less over time.
- **App sprawl** — separate mobile apps per function, each needing its own setup.

### QNAP

- **Security is the defining complaint.** DeadBolt, Checkmate and eCh0raix ransomware campaigns all
  targeted internet-exposed QNAP devices via unpatched flaws, encrypting user data at scale.
  Critical command-injection CVEs have recurred, including CVE-2023-23368 at CVSS 9.8, with further
  QTS and QuTS hero vulnerabilities disclosed at Pwn2Own 2025. QNAP has since added a Security Center
  with ransomware detection, but for many owners the trust is gone.
- **Interface density** — powerful, but a lot of surface area for a home user to absorb.

### UGREEN

- **A thin app catalogue.** UGOS Pro offered roughly 29 apps for the DXP4800 Pro against hundreds on DSM
  and QTS; reviewers note you end up in Docker for anything beyond the basics.
- **Basic backup tooling** relative to Hyper Backup or HBS 3.
- **A short security track record** — the company is new to this category, and reviewers say so directly.
- Hardware is consistently praised; the software is where the criticism lands.

### TerraMaster and Asustor

- **TOS reads as a work in progress**, with few officially supported applications.
- **Slow, unreliable mobile backup** — one owner reported 450 of 18,472 files transferred after five
  hours, with original photo timestamps lost in the process.

### unRAID and TrueNAS

- **Setup and maintenance burden.** Both trade convenience for flexibility, and buyers repeatedly choose
  turnkey systems over them for exactly that reason.
- **Weaker consumer-facing mobile apps** — strong storage engineering, thinner client experience.

### macOS Finder

- **A poor SMB client.** Users report authentication dialogs taking up to two minutes to appear and
  several more minutes to enumerate a folder — after which performance is fine. Apple's tightened SMB
  security requirements have broken interoperability with third-party servers.
- **No cut/paste in the context menu** — the move gesture is a hidden `Option-Cmd-V` that switchers
  never discover.

### Windows File Explorer

- **Slow.** Sluggish launches, laggy search, delayed context menus — a long-running and loud complaint.
  The Windows 11 preload fix reportedly doubled RAM use without meaningfully improving responsiveness.
- **Search is widely considered broken**, which pushes users to third-party tools.

### Cross-cutting

- **"One-time setup and forget about it"** is what home users say they want, and what almost nobody
  delivers. Setup complexity is the most consistent theme across every vendor's forums.
- **Photo backup is the feature people buy for and the one most likely to disappoint** — apps that can't
  see the SD card, that need manual launching, that mangle timestamps, that stall.

---

## What the complaints tell us

1. **Trust is the product.** QNAP's ransomware history and Synology's lock-in reversal did more damage
   than any missing feature. Our security posture and our refusal to lock hardware are competitive
   assets, not just engineering hygiene — but that raises the cost of shipping remote access, sharing
   or multi-user carelessly. Item 6 on the list above (2FA) is where this bites first.
2. **Photo backup has to be excellent or not exist.** It is the single most-complained-about feature
   across every vendor. Shipping a mediocre version buys us the complaints without the credit — it needs
   to run in the background, survive reboots, preserve original timestamps, and not require opening the
   app.
3. **Simplicity is a real position.** UGOS is criticized for a thin app catalogue while turnkey NAS OSes
   as a category are chosen *over* TrueNAS and unRAID precisely because they're simpler. The lesson is
   not "ship 300 apps" — it's that the things Quark does should need no configuration. One coherent app
   is an advantage worth defending against the temptation to grow an app store.
4. **Some gaps are table stakes and some are competitors' self-inflicted wounds.** Multi-user, SMB,
   share links and trash are table stakes — buyers will not weigh them, they will just leave. Surveillance
   stations, VMs and iSCSI are not, and chasing them would trade away the simplicity in point 3.
5. **The file-manager baseline is easy to underrate.** Finder and Explorer set expectations about copy,
   sortable columns, and preview-on-spacebar that no NAS vendor gets credit for meeting — but that
   everyone gets punished for missing. The two cheap items at the end of the feature list are worth more
   than their size suggests.

---

## Sources

Competitor capabilities and complaints:

- [Ugreen NASync DXP4800 Pro review — IT Pro](https://www.itpro.com/infrastructure/servers-and-storage/ugreen-nasync-dxp4800-pro-review-this-superbly-built-nas-offers-a-powerful-hardware-package-but-comes-up-short-in-the-app-department)
- [Ugreen NASync iDX6011 Pro Review, UGOS Pro — TechPowerUp](https://www.techpowerup.com/review/ugreen-nasync-idx6011-pro/7.html)
- [Synology DSM 7.2 Enhances Security, Performance, and Accessibility — StorageReview](https://www.storagereview.com/news/synology-dsm-7-2-enhances-security-performance-and-accessibility)
- [Synology releases DSM 7.2.2 — Synology](https://www.synology.com/en-global/company/news/article/DSM722)
- [Synology Reverses Course on Some Drive Restrictions — Slashdot](https://hardware.slashdot.org/story/25/10/08/1723232/synology-reverses-course-on-some-drive-restrictions)
- [Synology 2025 NAS Hard Drive and SSD Lock In Confirmed — NAS Compares](https://nascompares.com/2025/04/16/synology-2025-nas-hard-drive-and-ssd-lock-in-confirmed-bye-bye-seagate-and-wd/)
- [Synology reversing its hard drive policy — Android Authority](https://www.androidauthority.com/synology-third-party-drive-policy-3605210/)
- [QNAP devices hit by DeadBolt ransomware again — TechTarget](https://www.techtarget.com/searchsecurity/news/252518453/QNAP-devices-hit-by-DeadBolt-ransomware-again)
- [QNAP warns of critical command injection flaws in QTS OS, apps — BleepingComputer](https://www.bleepingcomputer.com/news/security/qnap-warns-of-critical-command-injection-flaws-in-qts-os-apps/)
- [Multiple Vulnerabilities in QTS and QuTS hero, Pwn2Own 2025 — QNAP QSA-25-45](https://www.qnap.com/en/security-advisory/qsa-25-45)
- [QNAP adds NAS ransomware protection to latest QTS version — BleepingComputer](https://www.bleepingcomputer.com/news/security/qnap-adds-nas-ransomware-protection-to-latest-qts-version/)
- [Synology Photos vs Google Photos — Tech-Critter](https://www.tech-critter.com/synology-photos-vs-google-photos-which-is-better-and-why/)
- [Windows 11's updated File Explorer remains painfully slow — TechSpot](https://www.techspot.com/news/110446-windows-11-updated-file-explorer-remains-painfully-slow.html)
- [Complaints about Windows 11's fix for File Explorer sluggishness — TechRadar](https://www.techradar.com/computing/windows/complaints-about-windows-11s-fix-for-file-explorer-sluggishness-are-overblown-but-they-underline-a-fundamental-problem-with-the-os)
- [Slow SMB browsing — Apple Community](https://discussions.apple.com/thread/254805549)
- [Finder vs. Windows Explorer — How-To Geek](https://www.howtogeek.com/finder-vs-windows-explorer-differences-every-mac-switcher-needs-to-know/)
- [Samba vs NFS vs WebDAV: Self-Hosted File Sharing Guide — Pi Stack](https://www.pistack.xyz/posts/2026-04-24-samba-vs-nfs-vs-webdav-self-hosted-file-sharing-guide-2026/)
- [TNAS mobile backup — TerraMaster Forum](https://forum.terra-master.com/en/viewtopic.php?t=3949)
- [Android automatic backup for files/folders/photos — SynoForum](https://www.synoforum.com/threads/android-automatic-backup-for-files-folders-photos.4542/)

Quark capabilities, verified in-tree: [`docs/user-journeys/`](user-journeys/README.md),
`internal/server/api/v0/`, `pkg/util/storageutil/trash.go`, `pkg/util/authutil/authutil.go`,
`pkg/util/remoteutil/`, `pkg/util/photoutil/`, `pkg/util/videoutil/`, `pkg/util/searchutil/`.
