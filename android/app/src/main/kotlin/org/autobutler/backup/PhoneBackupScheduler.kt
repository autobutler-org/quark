package org.autobutler.backup

import android.content.Context
import android.provider.MediaStore
import androidx.core.content.ContextCompat
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequest
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkInfo
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

/**
 * Schedules phone backup's two Android triggers (#4165): a periodic job about
 * every hour, and a job that waits on MediaStore and fires soon after a new
 * photo or video appears. Both run [PhoneBackupWorker].
 *
 * **Wi-Fi only** is the jobs' unmetered-network constraint. **Only while
 * charging** is not a constraint: WorkManager's charging constraint is false
 * for a phone plugged in but held at a charge limit, so the worker checks
 * whether the phone is plugged in itself, before it starts an engine.
 *
 * The conditions are kept in shared preferences so the worker can read them
 * back, and so their absence means backup is off.
 */
object PhoneBackupScheduler {
    private const val PERIODIC_WORK = "phone_backup_periodic"
    private const val NEW_MEDIA_WORK = "phone_backup_new_media"

    /** Tags the new-media job, which has to re-arm itself after each run. */
    const val NEW_MEDIA_TAG = "phone_backup_new_media"

    private const val PREFS = "phone_backup_background"
    private const val KEY_SCHEDULED = "scheduled"
    private const val KEY_WIFI_ONLY = "wifiOnly"

    /** **Only while charging** in [conditions]. */
    const val KEY_CHARGING_ONLY = "chargingOnly"

    /**
     * Stores [wifiOnly] and [chargingOnly], schedules both jobs under them and
     * calls [onDone] on the main thread.
     *
     * A running new-media worker is never canceled: when one is running, or the
     * conditions did not change, the queued job is kept, and a running worker
     * re-arms the next one from the stored conditions when it ends.
     */
    fun schedule(context: Context, wifiOnly: Boolean, chargingOnly: Boolean, onDone: () -> Unit) {
        val unchanged = conditions(context) == mapOf(KEY_WIFI_ONLY to wifiOnly, KEY_CHARGING_ONLY to chargingOnly)
        prefs(context).edit()
            .putBoolean(KEY_SCHEDULED, true)
            .putBoolean(KEY_WIFI_ONLY, wifiOnly)
            .putBoolean(KEY_CHARGING_ONLY, chargingOnly)
            .apply()
        val work = WorkManager.getInstance(context)
        val periodic = PeriodicWorkRequestBuilder<PhoneBackupWorker>(1, TimeUnit.HOURS)
            .setConstraints(constraints(wifiOnly).build())
            .build()
        // UPDATE keeps the hourly cadence and swaps in the new constraints.
        work.enqueueUniquePeriodicWork(PERIODIC_WORK, ExistingPeriodicWorkPolicy.UPDATE, periodic)
        val infos = work.getWorkInfosForUniqueWork(NEW_MEDIA_WORK)
        infos.addListener({
            val running = infos.get().any { it.state == WorkInfo.State.RUNNING }
            // REPLACE swaps only a queued job's constraints. A worker that
            // starts between this read and the enqueue is the one case it
            // cancels; the hourly job picks up what that run missed.
            val policy = if (unchanged || running) ExistingWorkPolicy.KEEP else ExistingWorkPolicy.REPLACE
            newMediaRequest(context, immediately = false)?.let { work.enqueueUniqueWork(NEW_MEDIA_WORK, policy, it) }
            onDone()
        }, ContextCompat.getMainExecutor(context))
    }

    /** Forgets the conditions and cancels both jobs. */
    fun cancel(context: Context) {
        prefs(context).edit().clear().apply()
        val work = WorkManager.getInstance(context)
        work.cancelUniqueWork(PERIODIC_WORK)
        work.cancelUniqueWork(NEW_MEDIA_WORK)
    }

    /** The scheduled conditions as the Dart side reads them, or null when backup is off. */
    fun conditions(context: Context): Map<String, Boolean>? {
        val prefs = prefs(context)
        if (!prefs.getBoolean(KEY_SCHEDULED, false)) return null
        return mapOf(
            KEY_WIFI_ONLY to prefs.getBoolean(KEY_WIFI_ONLY, true),
            KEY_CHARGING_ONLY to prefs.getBoolean(KEY_CHARGING_ONLY, false),
        )
    }

    /**
     * Queues the next new-media job behind the one that is ending. A
     * content-URI trigger fires once and only sees changes made after its job
     * may run, so when photos arrived during the run, [immediately] queues a
     * plain run instead, which re-arms the trigger when it ends.
     */
    fun rearmNewMedia(context: Context, immediately: Boolean) {
        val request = newMediaRequest(context, immediately) ?: return
        WorkManager.getInstance(context)
            .enqueueUniqueWork(NEW_MEDIA_WORK, ExistingWorkPolicy.APPEND_OR_REPLACE, request)
    }

    private fun newMediaRequest(context: Context, immediately: Boolean): OneTimeWorkRequest? {
        val conditions = conditions(context) ?: return null
        val constraints = constraints(conditions.getValue(KEY_WIFI_ONLY))
        if (!immediately) {
            constraints
                .addContentUriTrigger(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, true)
                .addContentUriTrigger(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, true)
                // Wait for a burst of new shots to settle before running.
                .setTriggerContentUpdateDelay(30, TimeUnit.SECONDS)
                .setTriggerContentMaxDelay(2, TimeUnit.MINUTES)
        }
        return OneTimeWorkRequestBuilder<PhoneBackupWorker>()
            .setConstraints(constraints.build())
            .addTag(NEW_MEDIA_TAG)
            .build()
    }

    private fun constraints(wifiOnly: Boolean) =
        Constraints.Builder()
            .setRequiredNetworkType(if (wifiOnly) NetworkType.UNMETERED else NetworkType.CONNECTED)

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
