import Foundation

/// Every sentence the extension shows, in one place for translation. Each failure says what to do next, never
/// what broke, and names no key, cache or enrollment (docs/design/native-autofill-vault.md, "Failure UX").
/// No button opens Quark: whether a credential provider extension may open its app is not established, so the
/// text says to.
enum AutofillCopy {
    static let title = NSLocalizedString("autofill.title", value: "Quark", comment: "The list's title")

    static let faceIdReason = NSLocalizedString(
        "autofill.reason",
        value: "Fill a password from your Quark vault",
        comment: "Why Face ID or Touch ID is asked for"
    )

    static let locked = NSLocalizedString(
        "autofill.locked",
        value: "To fill passwords here, open Quark, unlock your vault, and turn on Face ID or Touch ID for it.",
        comment: "No vault this extension can open"
    )

    static let changed = NSLocalizedString(
        "autofill.changed",
        value: "Your fingerprints or face changed, so open Quark and unlock your vault with your password once.",
        comment: "A face or finger was enrolled or removed since the vault was last unlocked"
    )

    static let lockedOut = NSLocalizedString(
        "autofill.lockedOut",
        value: "Face ID or Touch ID is paused. Lock your phone, unlock it with your passcode, then try again.",
        comment: "Too many failed attempts"
    )

    static let noSavedLogins = NSLocalizedString(
        "autofill.noSavedLogins",
        value: "No saved logins yet.",
        comment: "The vault has no logins"
    )

    /// "No saved login for bank.example."
    static func noMatch(_ site: String) -> String {
        String(format: NSLocalizedString(
            "autofill.noMatch",
            value: "No saved login for %@.",
            comment: "The vault has no login for the site being filled"
        ), site)
    }

    /// The list footer when the vault on this phone has not been refreshed for a while.
    static func lastUpdated(_ date: Date) -> String {
        String(format: NSLocalizedString(
            "autofill.lastUpdated",
            value: "Last updated %@. Open Quark to refresh.",
            comment: "The saved logins may be out of date"
        ), DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none))
    }
}
