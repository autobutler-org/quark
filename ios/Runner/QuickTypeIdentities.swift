import AuthenticationServices
import Flutter
import Foundation

/// The QuickType bar's Quark logins (#3599), on the `org.autobutler/quicktype` channel that
/// `lib/services/quicktype_identities.dart` speaks.
///
/// `ASCredentialIdentityStore` keeps each identity's site and username in the clear, outside the vault's
/// encryption, so the Dart side calls `replace` only once the user has opted in, and `clear` on every event that
/// ends it. An identity is a domain, a username and a record identifier, `<accountKey>/<itemId>`, which the
/// credential provider extension looks up in the ciphertext cache; never a password or a full URL.
///
/// `replace` stores nothing while Quark is not the enabled AutoFill provider, and answers whether it stored. Any
/// identity that is not well formed fails the whole call, so a malformed list never half-replaces the store.
/// `clear` runs whatever the provider state. Channel errors carry a code and never a site or a username.
final class QuickTypeIdentities {
    static let channelName = "org.autobutler/quicktype"
    private static let recordPattern = try! NSRegularExpression(pattern: "^acct_[0-9a-f]{32}/[0-9]+$")

    /// Answers the channel on [messenger].
    static func register(with messenger: FlutterBinaryMessenger) {
        let identities = QuickTypeIdentities()
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
        channel.setMethodCallHandler { call, result in identities.handle(call, result: result) }
    }

    private let store = ASCredentialIdentityStore.shared

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "replace":
            let args = call.arguments as? [String: Any] ?? [:]
            guard let identities = Self.identities(args["identities"]) else {
                result(Self.failure("failed"))
                return
            }
            replace(identities, result: result)
        case "clear":
            store.removeAllCredentialIdentities { done, _ in
                DispatchQueue.main.async { result(done ? nil : Self.failure("failed")) }
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func replace(_ identities: [ASPasswordCredentialIdentity], result: @escaping FlutterResult) {
        store.getState { state in
            guard state.isEnabled else {
                DispatchQueue.main.async { result(false) }
                return
            }
            let done: (Bool, Error?) -> Void = { done, _ in
                DispatchQueue.main.async { result(done ? true : Self.failure("failed")) }
            }
            if #available(iOS 17.0, *) {
                self.store.replaceCredentialIdentities(identities, completion: done)
            } else {
                self.store.replaceCredentialIdentities(with: identities, completion: done)
            }
        }
    }

    /// The identities the channel sent, or nil when any of them is not a non-empty domain, a non-empty username
    /// and a record identifier as `VaultAutofillEntry.recordIdentifier` makes it.
    private static func identities(_ raw: Any?) -> [ASPasswordCredentialIdentity]? {
        guard let list = raw as? [[String: Any]] else { return nil }
        var identities: [ASPasswordCredentialIdentity] = []
        for entry in list {
            guard let domain = entry["domain"] as? String, !domain.isEmpty,
                  let username = entry["username"] as? String, !username.isEmpty,
                  let record = entry["record"] as? String,
                  recordPattern.firstMatch(in: record, range: NSRange(record.startIndex..., in: record)) != nil
            else { return nil }
            identities.append(ASPasswordCredentialIdentity(
                serviceIdentifier: ASCredentialServiceIdentifier(identifier: domain, type: .domain),
                user: username,
                recordIdentifier: record
            ))
        }
        return identities
    }

    private static func failure(_ code: String) -> FlutterError {
        FlutterError(code: code, message: nil, details: nil)
    }
}
