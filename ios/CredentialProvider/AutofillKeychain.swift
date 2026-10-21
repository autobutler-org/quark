import Foundation
import LocalAuthentication
import Security

/// Reads the vault key the app cached behind Face ID or Touch ID (#3595, `ios/Runner/VaultKeychain.swift`) from
/// the Keychain access group the app and this extension share. It only reads: deleting an item the enrolled
/// faces or fingers no longer open is the app's job, so the extension tells the user to open it.
///
/// Every key read shows the biometric prompt, with no passcode fallback, as the item's access control demands
/// (docs/design/native-autofill-vault.md, "iOS: a Keychain item with biometric access control"). One
/// `LAContext` serves every read of a fill, so one prompt covers every account.
final class AutofillKeychain {
    /// What one account's read found.
    enum Read {
        /// The key and the fingerprint the app stored beside it.
        case key([UInt8], fingerprint: [UInt8])
        /// No item for the account: biometric unlock is off for it.
        case missing
        /// The item is there but no longer opens: a face or finger was enrolled or removed.
        case changed
        /// The user canceled the prompt.
        case canceled
        /// Too many failed attempts; the passcode has to unlock the phone first.
        case lockedOut
        /// Anything else, which fills nothing.
        case failed
    }

    private static let service = "org.autobutler.quark.vault"

    private let accessGroup = Bundle.main.object(forInfoDictionaryKey: "QuarkKeychainAccessGroup") as? String
    private let context: LAContext

    /// A reader whose prompt shows `reason`.
    init(reason: String) {
        context = LAContext()
        context.localizedReason = reason
        // No "Enter Passcode": the item takes the biometric only.
        context.localizedFallbackTitle = ""
    }

    /// Reads `account`'s key. Blocks while the prompt is up, so it never runs on the main thread.
    func read(account: String) -> Read {
        guard hasItem(account) else { return .missing }
        var error: NSError?
        if !context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            switch LAError.Code(rawValue: error?.code ?? 0) {
            case .biometryLockout?: return .lockedOut
            case .biometryNotEnrolled?, .passcodeNotSet?: return .changed
            default: return .failed
            }
        }
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = context
        var item: CFTypeRef?
        switch SecItemCopyMatching(query as CFDictionary, &item) {
        case errSecSuccess:
            guard let attributes = item as? [String: Any],
                  let key = attributes[kSecValueData as String] as? Data,
                  let fingerprint = attributes[kSecAttrGeneric as String] as? Data
            else { return .failed }
            return .key(Array(key), fingerprint: Array(fingerprint))
        case errSecUserCanceled: return .canceled
        // The item is still listed but will not open: the enrolled faces or fingers changed.
        case errSecItemNotFound, errSecAuthFailed: return .changed
        default: return .failed
        }
    }

    /// Whether `account` has an item, read from its attributes with no prompt.
    private func hasItem(_ account: String) -> Bool {
        var query = baseQuery(account)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let silent = LAContext()
        silent.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = silent
        var item: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess
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
}
