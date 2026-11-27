package org.autobutler.backup

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.database.ContentObserver
import android.os.BatteryManager
import android.os.Build
import android.provider.MediaStore
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import org.autobutler.R
import java.text.NumberFormat
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

/**
 * One background phone backup wake (#4165). With **Only while charging** on,
 * a phone that is not plugged in ends the wake before any engine starts.
 * Otherwise it starts a headless Flutter engine at `phoneBackupBackgroundMain`
 * in `lib/services/phone_backup_background.dart`, which takes
 * [PhoneBackupRunLock] and calls the same run the foreground does, then waits
 * for it to say `finished`. A Dart side that goes silent without finishing is
 * given up on, so a dead isolate cannot hold the engine and the lock.
 *
 * A run long enough to report progress is promoted once to a foreground
 * service of type `dataSync`, as Android requires for long work; later
 * progress updates its notification in place.
 */
class PhoneBackupWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    private val finished = CompletableDeferred<String>()
    private val heard = AtomicLong()
    private val progress = MutableStateFlow<Pair<Int, Int>?>(null)
    private val count = NumberFormat.getIntegerInstance()
    private val notification by lazy {
        NotificationCompat.Builder(applicationContext, ensureChannel())
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setContentTitle(applicationContext.getString(R.string.phone_backup_notification_title))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
    }

    override suspend fun doWork(): Result {
        val chargingOnly =
            PhoneBackupScheduler.conditions(applicationContext)?.get(PhoneBackupScheduler.KEY_CHARGING_ONLY) == true
        val mediaArrived = if (chargingOnly && !isPluggedIn()) {
            Log.i(TAG, "background wake: notPluggedIn")
            false
        } else {
            runBackup()
        }
        // A content-URI trigger fires once; queue the next one behind this run.
        // A stopped worker was canceled, and whoever did that already
        // scheduled what comes next.
        if (!isStopped && tags.contains(PhoneBackupScheduler.NEW_MEDIA_TAG)) {
            PhoneBackupScheduler.rearmNewMedia(applicationContext, immediately = mediaArrived)
        }
        // Not a retry, even when the Dart side went silent: a retry would only
        // hang the same way, and the next wake tries again.
        return Result.success()
    }

    /** Runs one backup in a headless engine and answers whether new photos or
     * videos appeared while it ran, which the new-media trigger cannot see. */
    private suspend fun runBackup(): Boolean = coroutineScope {
        val mediaArrived = AtomicBoolean(false)
        val observer = object : ContentObserver(null) {
            override fun onChange(selfChange: Boolean) {
                mediaArrived.set(true)
            }
        }
        val resolver = applicationContext.contentResolver
        for (uri in MEDIA_URIS) resolver.registerContentObserver(uri, true, observer)
        val engine = withContext(Dispatchers.Main) { startEngine() }
        val notifier = launch { showProgress() }
        try {
            Log.i(TAG, "background wake: ${awaitFinished() ?: "gave up, the Dart side went silent"}")
        } finally {
            notifier.cancel()
            resolver.unregisterContentObserver(observer)
            withContext(NonCancellable + Dispatchers.Main) {
                // An engine that died mid-run must not leave the lock held.
                PhoneBackupRunLock.release(this@PhoneBackupWorker)
                engine.destroy()
            }
        }
        mediaArrived.get()
    }

    /**
     * Waits for `finished`, or answers null once the Dart side has said
     * nothing for a whole window: [START_TIMEOUT_MS] for its first call, then
     * [SILENCE_TIMEOUT_MS] between calls.
     */
    private suspend fun awaitFinished(): String? {
        var window = START_TIMEOUT_MS
        while (true) {
            val before = heard.get()
            withTimeoutOrNull(window) { finished.await() }?.let { return it }
            if (heard.get() == before) return null
            window = SILENCE_TIMEOUT_MS
        }
    }

    private fun startEngine(): FlutterEngine {
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(applicationContext)
        loader.ensureInitializationComplete(applicationContext, null)
        val engine = FlutterEngine(applicationContext)
        PhoneBackupChannel.install(applicationContext, engine.dartExecutor.binaryMessenger, owner = this, worker = this)
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(loader.findAppBundlePath(), ENTRY_LIBRARY, ENTRY_FUNCTION),
        )
        return engine
    }

    /** Promotes the run on its first progress, then updates the notification
     * at most once every [PROGRESS_INTERVAL_MS]. */
    private suspend fun showProgress() {
        var foreground: Boolean? = null
        progress.filterNotNull().collect { (done, total) ->
            val text = applicationContext.getString(
                R.string.phone_backup_notification_progress,
                count.format(done),
                count.format(total),
            )
            val shown = notification.setContentText(text).setProgress(total, done, false).build()
            if (foreground == null) {
                foreground = promote(shown)
            } else if (foreground == true) {
                applicationContext.getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, shown)
            }
            delay(PROGRESS_INTERVAL_MS)
        }
    }

    private suspend fun promote(shown: Notification): Boolean {
        val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ForegroundInfo(NOTIFICATION_ID, shown, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            ForegroundInfo(NOTIFICATION_ID, shown)
        }
        return try {
            setForeground(info)
            true
        } catch (e: IllegalStateException) {
            // Android 12+ can refuse to start a foreground service from the
            // background. The run carries on in the plain background window, and
            // what it does not reach the next wake picks up from the ledger.
            Log.w(TAG, "could not promote the backup run to the foreground", e)
            false
        }
    }

    /** Any call from the Dart side: it is still alive. */
    fun heardFromDart() {
        heard.incrementAndGet()
    }

    /** The Dart side's progress, shown in the foreground notification. */
    fun reportProgress(done: Int, total: Int) {
        progress.value = done to total
    }

    /** The Dart side is done; [outcome] names a `PhoneBackupWakeOutcome`. */
    fun finish(outcome: String) {
        finished.complete(outcome)
    }

    /** Plugged in, whether or not the battery is charging: a phone held at a
     * charge limit reports not charging while it sits on the charger. */
    private fun isPluggedIn(): Boolean {
        // A null receiver reads the sticky battery broadcast without registering.
        val battery = applicationContext.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        return (battery?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0) != 0
    }

    private fun ensureChannel(): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = applicationContext.getSystemService(NotificationManager::class.java)
            if (manager.getNotificationChannel(CHANNEL_ID) == null) {
                manager.createNotificationChannel(
                    NotificationChannel(
                        CHANNEL_ID,
                        applicationContext.getString(R.string.phone_backup_channel_name),
                        NotificationManager.IMPORTANCE_LOW,
                    ),
                )
            }
        }
        return CHANNEL_ID
    }

    private companion object {
        const val TAG = "PhoneBackupWorker"
        const val CHANNEL_ID = "phone_backup"
        const val NOTIFICATION_ID = 4165
        const val ENTRY_LIBRARY = "package:quark/services/phone_backup_background.dart"
        const val ENTRY_FUNCTION = "phoneBackupBackgroundMain"
        const val START_TIMEOUT_MS = 60_000L
        const val SILENCE_TIMEOUT_MS = 30 * 60_000L
        const val PROGRESS_INTERVAL_MS = 1_000L
        val MEDIA_URIS = listOf(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
        )
    }
}
