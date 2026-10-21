// cspell:words vaultkeystore
package org.autobutler

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone
import org.autobutler.autofill.AutofillSettings
import org.autobutler.vaultkeystore.VaultKeystore

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The device's IANA zone, which the app sends with each calendar event
        // so the Quark steps its occurrences in it (#3732). java.util.TimeZone
        // rather than java.time.ZoneId, which needs API 26 and minSdk is 24.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "org.autobutler.quark/time_zone")
            .setMethodCallHandler { call, result ->
                if (call.method == "localTimeZone") {
                    result.success(TimeZone.getDefault().id)
                } else {
                    result.notImplemented()
                }
            }
        // The vault key behind a strong biometric (#3595).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VaultKeystore.CHANNEL)
            .setMethodCallHandler(VaultKeystore(this))
        // Whether Quark is the autofill service, and the screen that makes it one (#3600).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AutofillSettings.CHANNEL)
            .setMethodCallHandler(AutofillSettings(this))
    }
}
