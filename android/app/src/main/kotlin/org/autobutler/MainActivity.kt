package org.autobutler

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.autobutler.backup.PhoneBackupChannel
import org.autobutler.backup.PhoneBackupRunLock
import java.util.TimeZone

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
        // Phone backup's background jobs and the run lock the foreground run
        // shares with them (#4165). The engine owns the lock it takes here.
        PhoneBackupChannel.install(
            this,
            flutterEngine.dartExecutor.binaryMessenger,
            owner = flutterEngine,
            onSchedule = ::requestNotificationPermission,
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        PhoneBackupRunLock.release(flutterEngine)
        super.cleanUpFlutterEngine(flutterEngine)
    }

    // A long background backup shows its progress in a notification, which
    // Android 13+ hides unless the app may post notifications.
    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) return
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_PERMISSION_REQUEST)
    }

    private companion object {
        const val NOTIFICATION_PERMISSION_REQUEST = 4165
    }
}
