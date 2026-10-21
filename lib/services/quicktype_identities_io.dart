/// The QuickType identity store's channel on iOS (#3599).
///
/// Only iOS has a store behind `org.autobutler/quicktype`; Android, desktop
/// builds and tests on a desktop host store nothing and never call it.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:quark/services/quicktype_identities.dart';

const _channel = MethodChannel(QuickTypeIdentities.channelName);

/// Whether this process runs on iOS. A test of the channel sets it.
@visibleForTesting
bool Function() isIOS = () => Platform.isIOS;

/// Whether there is a store: on iOS only.
bool isSupported() => isIOS();

/// Hands iOS [identities] to replace the store's with. A build without the
/// channel stores nothing.
Future<bool> replace(List<QuickTypeIdentity> identities) async {
  if (!isIOS()) return false;
  try {
    final stored = await _channel.invokeMethod<bool>('replace', {
      'identities': [
        for (final identity in identities)
          {
            'domain': identity.domain,
            'username': identity.username,
            'record': identity.record,
          },
      ],
    });
    return stored ?? false;
  } on MissingPluginException {
    return false;
  }
}

/// Asks iOS to empty the store. A build without the channel has none.
Future<void> clear() async {
  if (!isIOS()) return;
  try {
    await _channel.invokeMethod<void>('clear');
  } on MissingPluginException {
    return;
  }
}
