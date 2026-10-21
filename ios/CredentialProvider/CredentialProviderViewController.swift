import AuthenticationServices
import QuarkVaultCrypto
import UIKit

/// Quark's AutoFill Credential Provider (#3598, docs/design/native-autofill-vault.md): fills a login from the
/// vault into Safari and other apps with no Flutter engine, no network and no password.
///
/// It reads the ciphertext cache the app keeps in the app group container (#3596), reads the vault key the app
/// cached behind Face ID or Touch ID (#3595) with a prompt on every fill, checks the key against the
/// fingerprint stored beside it, opens the items to find the site's logins, and opens the password of the one
/// the user picks. It never runs Argon2id, so a vault with no cached key sends the user to the app. Every doubt
/// (no cache, no key, a key that opens nothing, a canceled prompt) fills nothing.
final class CredentialProviderViewController: ASCredentialProviderViewController {
    /// One account the prompt opened: its cache, its key while the list is on screen, and its matches.
    private final class Account {
        let cache: VaultAutofillCache
        private(set) var key: [UInt8]
        let entries: [VaultAutofillEntry]

        init(cache: VaultAutofillCache, key: [UInt8], entries: [VaultAutofillEntry]) {
            self.cache = cache
            self.key = key
            self.entries = entries
        }

        func wipe() {
            for i in key.indices { key[i] = 0 }
            key = []
        }
    }

    private enum Unlock {
        case accounts([Account])
        case message(String)
        case canceled
    }

    /// How old the cache may be before the list says so.
    private static let staleAfter: TimeInterval = 7 * 24 * 60 * 60

    private let list = CredentialListViewController()
    private let queue = DispatchQueue(label: "org.autobutler.quark.autofill")
    private var accounts: [Account] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        list.onCancel = { [weak self] in self?.cancel(.userCanceled) }
        list.onSelect = { [weak self] entry in self?.fill(entry) }
        let navigation = UINavigationController(rootViewController: list)
        addChild(navigation)
        navigation.view.frame = view.bounds
        navigation.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(navigation.view)
        navigation.didMove(toParent: self)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        forget()
    }

    /// The user opened Quark's list for `serviceIdentifiers`, the domains or URLs of what is being filled.
    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        let sites = serviceIdentifiers.map(\.identifier)
        list.show(.loading)
        unlock(sites: sites) { [weak self] accounts in
            guard let self else { return }
            let rows = accounts.flatMap { account in
                account.entries.map { entry in
                    CredentialListViewController.Row(
                        entry: entry,
                        title: entry.name.isEmpty ? entry.site : entry.name,
                        // Labeled by account only when there is more than one.
                        subtitle: accounts.count > 1 ? "\(entry.username) · \(account.cache.username)" : entry.username
                    )
                }
            }
            if rows.isEmpty {
                let site = sites.lazy.map(VaultHosts.hostOf).first(where: { !$0.isEmpty })
                self.list.show(.message(site.map(AutofillCopy.noMatch) ?? AutofillCopy.noSavedLogins))
                return
            }
            let oldest = accounts.compactMap(\.cache.syncedAt).min()
            let footer = oldest.flatMap { Date().timeIntervalSince($0) > Self.staleAfter ? AutofillCopy.lastUpdated($0) : nil }
            self.list.show(.rows(rows, footer: footer))
        }
    }

    /// A QuickType identity (#3599) was picked. Reading the key always shows Face ID or Touch ID, so there is no
    /// fill without the user: iOS calls ``prepareInterfaceToProvideCredential(for:)`` next.
    override func provideCredentialWithoutUserInteraction(for credentialIdentity: ASPasswordCredentialIdentity) {
        cancel(.userInteractionRequired)
    }

    /// Fills the QuickType identity (#3599) whose record identifier is a ``VaultAutofillEntry/recordIdentifier``.
    override func prepareInterfaceToProvideCredential(for credentialIdentity: ASPasswordCredentialIdentity) {
        let record = credentialIdentity.recordIdentifier
        list.show(.loading)
        unlock(sites: []) { [weak self] accounts in
            guard let self else { return }
            let entry = accounts.lazy.flatMap(\.entries).first(where: { $0.recordIdentifier == record })
            guard let entry else {
                self.cancel(.credentialIdentityNotFound)
                return
            }
            self.fill(entry)
        }
    }

    /// Opens every account's cache with its key behind one prompt, and hands `done` the accounts that opened,
    /// on the main thread. A state with nothing to fill is shown here and never reaches `done`.
    private func unlock(sites: [String], done: @escaping ([Account]) -> Void) {
        forget()
        queue.async {
            let outcome = Self.open(sites: sites)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch outcome {
                case let .accounts(accounts):
                    self.accounts = accounts
                    done(accounts)
                case let .message(text):
                    self.list.show(.message(text))
                case .canceled:
                    // Canceling is not an error: nothing is filled and nothing alarming is shown.
                    self.cancel(.userCanceled)
                }
            }
        }
    }

    private static func open(sites: [String]) -> Unlock {
        let caches = cacheDirectory().map { VaultAutofillCache.load(directory: $0) } ?? []
        if caches.isEmpty { return .message(AutofillCopy.locked) }
        let keychain = AutofillKeychain(reason: AutofillCopy.faceIdReason)
        var accounts: [Account] = []
        var changed = false
        for cache in caches {
            switch keychain.read(account: cache.accountKey) {
            case .key(var key, let fingerprint):
                // A key that is not the one the app fingerprinted, or that opens none of the items, is stale.
                if VaultAutofill.keyMatches(key, fingerprint: fingerprint),
                   let entries = VaultAutofill.entries(in: cache, matching: sites, vaultKey: key) {
                    accounts.append(Account(cache: cache, key: key, entries: entries))
                }
                for i in key.indices { key[i] = 0 }
            case .canceled:
                accounts.forEach { $0.wipe() }
                return .canceled
            case .lockedOut:
                accounts.forEach { $0.wipe() }
                return .message(AutofillCopy.lockedOut)
            case .changed:
                changed = true
            case .missing, .failed:
                break
            }
        }
        if !accounts.isEmpty { return .accounts(accounts) }
        return .message(changed ? AutofillCopy.changed : AutofillCopy.locked)
    }

    /// The cache directory in the app group container, nil when the build has no app group entitlement.
    private static func cacheDirectory() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: VaultAutofillCache.appGroup)?
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(VaultAutofillCache.directoryName, isDirectory: true)
    }

    /// Opens the picked entry's password and fills it, or fills nothing when it no longer opens.
    private func fill(_ entry: VaultAutofillEntry) {
        guard let account = accounts.first(where: { $0.cache.accountKey == entry.accountKey }),
              let credential = VaultAutofill.credential(for: entry, in: account.cache, vaultKey: account.key)
        else {
            cancel(.credentialIdentityNotFound)
            return
        }
        forget()
        extensionContext.completeRequest(
            withSelectedCredential: ASPasswordCredential(user: credential.username, password: credential.password),
            completionHandler: nil
        )
    }

    private func cancel(_ code: ASExtensionError.Code) {
        forget()
        extensionContext.cancelRequest(withError: NSError(domain: ASExtensionErrorDomain, code: code.rawValue))
    }

    /// Drops every key this extension holds.
    private func forget() {
        accounts.forEach { $0.wipe() }
        accounts = []
    }
}
