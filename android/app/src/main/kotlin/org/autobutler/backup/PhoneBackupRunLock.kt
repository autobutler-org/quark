package org.autobutler.backup

/**
 * The one lock every phone backup run takes (#4165), whether the app's engine
 * started it in the foreground or [PhoneBackupWorker]'s headless engine did in
 * the background. Both engines run in this process, so a process-wide holder
 * is what keeps them from overlapping; a killed process drops the lock with it.
 */
object PhoneBackupRunLock {
    private var holder: Any? = null

    /**
     * Takes the lock for [owner], or answers false when anyone holds it,
     * [owner] included: every foreground run shares the app's engine as its
     * owner, so a second run from the same engine has to be refused too.
     */
    @Synchronized
    fun tryAcquire(owner: Any): Boolean {
        if (holder != null) return false
        holder = owner
        return true
    }

    /** Gives the lock back if [owner] holds it, so an engine that went away
     * mid-run cannot leave it held. */
    @Synchronized
    fun release(owner: Any) {
        if (holder === owner) holder = null
    }
}
