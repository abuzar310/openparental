package app.monii.managed.sync

import android.content.Context
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import app.monii.managed.enforcement.PolicyRules
import java.util.concurrent.TimeUnit

object ScheduledSnapshotScheduler {
    private const val WORK_NAME = "scheduled_snapshot"

    /** Call after SET_POLICY or on supervisor boot. */
    fun applyFromPolicy(context: Context) {
        val mins = PolicyRules.load(context)?.snapshotIntervalMinutes ?: 0
        val wm = WorkManager.getInstance(context)
        if (mins <= 0) {
            wm.cancelUniqueWork(WORK_NAME)
            return
        }
        // ponytail: WorkManager periodic minimum is 15 minutes.
        val interval = mins.coerceAtLeast(15).toLong()
        val request = PeriodicWorkRequestBuilder<ScheduledSnapshotWorker>(interval, TimeUnit.MINUTES)
            .setConstraints(
                Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED)
                    .build(),
            )
            .build()
        wm.enqueueUniquePeriodicWork(
            WORK_NAME,
            ExistingPeriodicWorkPolicy.UPDATE,
            request,
        )
    }
}
