package org.autobutler.autofill

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.autofill.AutofillManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The `org.autobutler/autofill` channel `lib/services/autofill_settings.dart` speaks (#3600): whether Quark
 * is this device's autofill service, and the system screen that makes it one.
 *
 * `status` answers `unsupported` before API 26 or where the device has no autofill, `enabled` when Quark is
 * the service, and `disabled` otherwise. `openSettings` opens `ACTION_REQUEST_SET_AUTOFILL_SERVICE` for
 * Quark's package, and fails with `unavailable` where no screen answers it.
 */
class AutofillSettings(private val activity: Activity) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL = "org.autobutler/autofill"
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> result.success(status())
            "openSettings" -> openSettings(result)
            else -> result.notImplemented()
        }
    }

    private fun status(): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return "unsupported"
        val manager = activity.getSystemService(AutofillManager::class.java)
        return when {
            manager == null || !manager.isAutofillSupported -> "unsupported"
            manager.hasEnabledAutofillServices() -> "enabled"
            else -> "disabled"
        }
    }

    private fun openSettings(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return result.error("unavailable", null, null)
        try {
            activity.startActivity(
                Intent(Settings.ACTION_REQUEST_SET_AUTOFILL_SERVICE, Uri.parse("package:${activity.packageName}")),
            )
            result.success(null)
        } catch (_: ActivityNotFoundException) {
            result.error("unavailable", null, null)
        }
    }
}
