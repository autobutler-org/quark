import 'package:quark/services/quicktype_identities_stub.dart'
    if (dart.library.io) 'package:quark/services/quicktype_identities_io.dart'
    as impl;

/// One login offered in the iOS QuickType bar: the site's [domain], the
/// [username], and the [record] the AutoFill extension finds the item by,
/// `<accountKey>/<itemId>`. Never a password, and never the full URL.
typedef QuickTypeIdentity = ({String domain, String username, String record});

/// iOS's credential identity store (#3599), over the
/// `org.autobutler/quicktype` channel (`ios/Runner/QuickTypeIdentities.swift`).
///
/// The store keeps every identity's site and username unencrypted, outside
/// the vault, which is why only `QuickTypeController` calls [replace], and
/// only after the user opts in. [replace] stores nothing while Quark is not
/// the enabled AutoFill provider and says whether it stored. Everywhere but
/// iOS there is no store: [isSupported] is false, and neither call reaches a
/// channel.
abstract final class QuickTypeIdentities {
  /// The platform channel's name.
  static const channelName = 'org.autobutler/quicktype';

  /// Whether this device has a QuickType identity store.
  static bool get isSupported => impl.isSupported();

  /// Replaces every identity in the store with [identities]. Returns false
  /// when nothing was stored because Quark is not the AutoFill provider, or
  /// there is no store. Throws when the store refused.
  static Future<bool> replace(List<QuickTypeIdentity> identities) =>
      impl.replace(identities);

  /// Removes every identity Quark put in the store. Throws when the store
  /// refused.
  static Future<void> clear() => impl.clear();
}
