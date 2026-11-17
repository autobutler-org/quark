package org.autobutler.backup

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Answers `org.autobutler.quark/phone_backup_background`, the channel
 * `lib/services/phone_backup_background.dart` speaks (#4165). The app's engine
 * and each worker's headless engine install it, each as its own [owner] of the
 * shared [PhoneBackupRunLock]. A [worker] is present only in the background,
 * where it takes `progress` and `finished`, and where every call counts as a
 * sign that the Dart side is still alive.
 */
object PhoneBackupChannel {
    const val NAME = "org.autobutler.quark/phone_backup_background"

    /** Installs the handler on [messenger]; [onSchedule] runs after a `schedule`. */
    fun install(
        context: Context,
        messenger: BinaryMessenger,
        owner: Any,
        worker: PhoneBackupWorker? = null,
        onSchedule: () -> Unit = {},
    ) {
        val app = context.applicationContext
        MethodChannel(messenger, NAME).setMethodCallHandler { call, result ->
            worker?.heardFromDart()
            when (call.method) {
                "schedule" -> PhoneBackupScheduler.schedule(
                    app,
                    wifiOnly = call.argument<Boolean>("wifiOnly") ?: true,
                    chargingOnly = call.argument<Boolean>("chargingOnly") ?: false,
                ) {
                    onSchedule()
                    result.success(null)
                }
                "cancel" -> {
                    PhoneBackupScheduler.cancel(app)
                    result.success(null)
                }
                "conditions" -> result.success(PhoneBackupScheduler.conditions(app))
                "tryAcquireRunLock" -> result.success(PhoneBackupRunLock.tryAcquire(owner))
                "releaseRunLock" -> {
                    PhoneBackupRunLock.release(owner)
                    result.success(null)
                }
                "progress" -> {
                    worker?.reportProgress(call.argument<Int>("done") ?: 0, call.argument<Int>("total") ?: 0)
                    result.success(null)
                }
                "finished" -> {
                    worker?.finish(call.arguments as? String ?: "")
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
