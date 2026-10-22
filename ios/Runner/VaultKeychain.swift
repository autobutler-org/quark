import Flutter
import Foundation
import LocalAuthentication
import Security

/// The vault key behind Face ID or Touch ID (#3595), on the `org.autobutler/vault_keystore` channel that
/// `lib/services/vault_biometric.dart` speaks (docs/design/native-autofill-vault.md, Decision 2).
///
/// One generic-password item per account in the `org.autobutler.quark.vault` service, in the Keychain access
/// group the credential provider extension will share (`QuarkKeychainAccessGroup` in Info.plist). Its access
/// control is `WhenPasscodeSetThisDeviceOnly` with `.biometryCurrentSet`: never synced or backed up, deleted
/// by iOS if the passcode is turned off, unreadable once a face or finger is enrolled or removed, and with no
/// passcode fallback. Every read shows the biometric prompt. The key's fingerprint sits in the item's
/// `kSecAttrGeneric`, which reads without a prompt.
///
/// Keychain items outlive the app, so the first launch after an install deletes every item a previous
/// install left. Channel errors carry a code the Dart side reads as a `VaultBiometricFailure` and never a
/// message: nothing here puts key material into a reply or the log.
final class VaultKeychain {
    static let channelName = "org.autobutler/vault_keystore"
    static let service = "org.autobutler.quark.vault"
    private static let installedFlag = "QuarkVaultKeychainInstalled"
    private static let accountPattern = try! NSRegularExpression(pattern: "^acct_[0-9a-f]{32}$")

    private let accessGroup = Bundle.main.object(forInfoDictionaryKey: "QuarkKeychainAccessGroup") as? String
    private let queue = DispatchQueue(label: "org.autobutler.quark.vault-keychain")

    /// Answers the channel on [messenger], after clearing what a previous install left.
    static func register(with messenger: FlutterBinaryMessenger) {
        let keychain = VaultKeychain()
        if !UserDefaults.standard.bool(forKey: installedFlag) {
            _ = keychain.delete(account: nil)
            UserDefaults.standard.set(true, forKey: installedFlag)
        }
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
        channel.setMethodCallHandler { call, result in keychain.handle(call, result: result) }
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        let account = args["account"] as? String
        // Keychain reads with a prompt block, so every call runs off the main thread.
        queue.async {
            let reply: Any?
            if call.method == "support" {
                reply = self.support()
            } else if call.method == "delete" && account == nil {
                reply = self.delete(account: nil)
            } else if let account = self.valid(account) {
                switch call.method {
                case "storedFingerprint": reply = self.storedFingerprint(account)
                case "store": reply = self.store(account: account, args: args)
                case "read": reply = self.read(account: account, args: args)
                case "delete": reply = self.delete(account: account)
                default: reply = FlutterMethodNotImplemented
                }
            } else {
                reply = Self.failure("failed")
            }
            DispatchQueue.main.async { result(reply) }
        }
    }

    private func support() -> [String: String] {
        let context = LAContext()
        var error: NSError?
        let can = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        let kind: String
        switch context.biometryType {
        case .faceID: kind = "faceId"
        case .touchID: kind = "touchId"
        default: kind = "biometrics"
        }
        let status: String
        if can {
            status = "available"
        } else {
            switch LAError.Code(rawValue: error?.code ?? 0) {
            case .biometryNotEnrolled?, .passcodeNotSet?: status = "notEnrolled"
            // Locked out for now, but enrolled: the read says so when it happens.
            case .biometryLockout?: status = "available"
            default: status = "unavailable"
            }
        }
        return ["status": status, "kind": kind]
    }

    private func storedFingerprint(_ account: String) -> Any? {
        var query = baseQuery(account)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let attributes = item as? [String: Any],
              let fingerprint = attributes[kSecAttrGeneric as String] as? Data
        else {
            return status == errSecItemNotFound || status == errSecSuccess ? nil : Self.failure("failed")
        }
        return FlutterStandardTypedData(bytes: fingerprint)
    }

    private func store(account: String, args: [String: Any]) -> Any? {
        guard var key = (args["key"] as? FlutterStandardTypedData)?.data,
              let fingerprint = (args["fingerprint"] as? FlutterStandardTypedData)?.data,
              key.count == 32, fingerprint.count == 16
        else { return Self.failure("failed") }
        defer { key.resetBytes(in: 0..<key.count) }
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .biometryCurrentSet, &error
        ) else { return Self.failure("unavailable") }
        // One account at a time: the active one's replaces every other.
        _ = delete(account: nil)
        var query = baseQuery(account)
        query[kSecAttrAccessControl as String] = access
        query[kSecAttrGeneric as String] = fingerprint
        query[kSecValueData as String] = key
        switch SecItemAdd(query as CFDictionary, nil) {
        case errSecSuccess: return nil
        // No passcode, or a build without the access group entitlement.
        case errSecAuthFailed, errSecMissingEntitlement, errSecNotAvailable: return Self.failure("unavailable")
        default: return Self.failure("failed")
        }
    }

    private func read(account: String, args: [String: Any]) -> Any? {
        let context = LAContext()
        context.localizedReason = args["reason"] as? String ?? ""
        context.localizedCancelTitle = args["cancel"] as? String
        // No "Enter Passcode": the item takes the biometric only.
        context.localizedFallbackTitle = ""
        var error: NSError?
        if !context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            switch LAError.Code(rawValue: error?.code ?? 0) {
            case .biometryLockout?: return Self.failure("lockedOut")
            case .biometryNotEnrolled?, .passcodeNotSet?:
                _ = delete(account: nil)
                return Self.failure("invalidated")
            default: return Self.failure("unavailable")
            }
        }
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = context
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let attributes = item as? [String: Any],
                  let key = attributes[kSecValueData as String] as? Data,
                  let fingerprint = attributes[kSecAttrGeneric as String] as? Data
            else { return Self.failure("failed") }
            return ["key": FlutterStandardTypedData(bytes: key), "fingerprint": FlutterStandardTypedData(bytes: fingerprint)]
        case errSecUserCanceled: return Self.failure("canceled")
        case errSecItemNotFound, errSecAuthFailed:
            // The item is still listed but will not open: the enrolled faces or fingers changed.
            if storedFingerprint(account) is FlutterStandardTypedData {
                _ = delete(account: nil)
                return Self.failure("invalidated")
            }
            return Self.failure(status == errSecItemNotFound ? "missing" : "failed")
        default: return Self.failure("failed")
        }
    }

    /// Deletes [account]'s item, or every item in the service for nil.
    private func delete(account: String?) -> Any? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
        ]
        if let account { query[kSecAttrAccount as String] = account }
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound ? nil : Self.failure("failed")
    }

    private func baseQuery(_ account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }

    /// [account] when it is an account key as `VaultCache.accountKey` makes it, else nil.
    private func valid(_ account: String?) -> String? {
        guard let account else { return nil }
        let range = NSRange(account.startIndex..., in: account)
        return Self.accountPattern.firstMatch(in: account, range: range) == nil ? nil : account
    }

    private static func failure(_ code: String) -> FlutterError {
        FlutterError(code: code, message: nil, details: nil)
    }
}
