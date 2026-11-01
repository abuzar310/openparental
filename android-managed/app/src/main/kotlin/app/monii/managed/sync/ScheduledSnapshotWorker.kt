package app.monii.managed.sync

import android.content.Context
import android.util.Base64
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import app.monii.managed.accessibility.MonitorAccessibilityService
import app.monii.managed.enforcement.PolicyRules
import app.monii.managed.identity.DeviceStore
import app.monii.managed.net.ContentItemDto
import app.monii.managed.net.IngestContentRequest
import app.monii.managed.repo.MoniiRepository
import kotlinx.coroutines.suspendCancellableCoroutine
import java.time.Instant
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume

/**
 * FlashGet-style scheduled screen snapshots (metadata + JPEG to parent feed).
 */
class ScheduledSnapshotWorker(
    context: Context,
    params: WorkerParameters,
) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        val rules = PolicyRules.load(applicationContext)
        if (rules == null || rules.snapshotIntervalMinutes <= 0) {
            return Result.success()
        }
        if (DeviceStore(applicationContext).deviceId() == null) {
            return Result.success()
        }

        val jpeg = captureScreenshot() ?: return Result.retry()
        val b64 = Base64.encodeToString(jpeg, Base64.NO_WRAP)
        return try {
            val repo = MoniiRepository(applicationContext, DeviceStore(applicationContext))
            repo.ingestContentDirect(
                ContentItemDto(
                    source = "scheduled_snapshot",
                    body = b64,
                    matched = null,
                    counterparty = "Scheduled snapshot",
                    occurredAt = Instant.now().toString(),
                ),
            )
            Result.success()
        } catch (_: Exception) {
            Result.retry()
        }
    }

    private suspend fun captureScreenshot(): ByteArray? = suspendCancellableCoroutine { cont ->
        val service = MonitorAccessibilityService.instance
        if (service == null) {
            cont.resume(null)
            return@suspendCancellableCoroutine
        }
        val latch = CountDownLatch(1)
        var bytes: ByteArray? = null
        service.captureScreenshot(QUALITY) { jpeg ->
            bytes = jpeg
            latch.countDown()
        }
        Thread {
            val ok = latch.await(8, TimeUnit.SECONDS)
            if (cont.isActive) cont.resume(if (ok) bytes else null)
        }.start()
    }

    private companion object {
        const val QUALITY = 55
    }
}
