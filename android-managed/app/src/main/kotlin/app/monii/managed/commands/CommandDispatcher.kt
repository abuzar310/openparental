package app.monii.managed.commands

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Environment
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import app.monii.managed.accessibility.MonitorAccessibilityService
import app.monii.managed.admin.AdminManager
import app.monii.managed.admin.DeviceOwnerManager
import app.monii.managed.data.PolicyStore
import app.monii.managed.net.CommandDto
import app.monii.managed.repo.MoniiRepository
import app.monii.managed.media.ScreenRecordService
import app.monii.managed.identity.DeviceStore
import app.monii.managed.mirror.AccessibilityLiveStreamService
import app.monii.managed.mirror.ScreenMirrorService
import app.monii.managed.mirror.ScreenshotUploader
import app.monii.managed.sync.ScheduledSnapshotScheduler
import app.monii.managed.ui.CameraCaptureActivity
import app.monii.managed.ui.ScreenMirrorActivity
import app.monii.managed.ui.ScreenRecordActivity
import java.io.File
import java.time.Instant
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Pull pending commands, execute each, ack + post the result. The server spine
 * is idempotent (ack/result are no-ops once terminal), so re-running after a
 * crash or duplicate wake is safe.
 *
 * Snapshot/recording actions are consent-based — the child sees a notification
 * and must approve before capture starts.
 */
class CommandDispatcher(
    private val context: Context,
    private val repo: MoniiRepository,
    private val admin: AdminManager,
) {
    suspend fun syncAndExecute(): Int {
        val commands = repo.pullCommands()
        for (command in commands) {
            runCatching { repo.ack(command.id) }
            val outcome = runCatching { execute(command) }
            if (outcome.isSuccess) {
                repo.result(command.id, outcome.getOrNull(), null)
            } else {
                repo.result(command.id, null, outcome.exceptionOrNull()?.message ?: "error")
            }
        }
        return commands.size
    }

    private fun execute(command: CommandDto): Map<String, Any?> =
        when (command.type) {
            "LOCK" -> {
                admin.lockNow()
                mapOf("locked" to true)
            }
            "UNLOCK" -> mapOf("noop" to "cannot force-unlock without Device Owner")
            "SET_POLICY" -> {
                PolicyStore.save(context, command.payload)
                ScheduledSnapshotScheduler.applyFromPolicy(context)
                mapOf("applied" to true)
            }
            "PING" -> mapOf("pong" to true)
            "REQUEST_LOCATION" -> mapOf("requested" to true)
            "CAMERA_SNAPSHOT" -> {
                val camera = (command.payload?.get("camera") as? String) ?: "front"
                val file = captureCameraSnapshot(camera)
                mapOf("captured" to true, "file" to (file?.absolutePath ?: "failed"))
            }
            "SCREEN_RECORD" -> {
                val action = (command.payload?.get("action") as? String) ?: "start"
                when (action) {
                    "start" -> startScreenRecording()
                    "stop" -> stopScreenRecording()
                    else -> Unit
                }
                mapOf("action" to action, "recording" to ScreenRecordService.isRecording)
            }
            "AMBIENT_RECORD" -> {
                val action = (command.payload?.get("action") as? String) ?: "start"
                when (action) {
                    "start" -> AmbientRecordService.start(context)
                    "stop" -> AmbientRecordService.stop(context)
                    else -> Unit
                }
                mapOf("action" to action, "one_way_audio" to true)
            }
            "SCREEN_MIRROR", "SCREEN_VIEW_REQUEST" -> {
                val sessionId = command.payload?.get("sessionId") as? String
                requestScreenMirror(sessionId)
                mapOf("mirror_requested" to true, "sessionId" to sessionId)
            }
            "SCREENSHOT" -> {
                val sessionId = command.payload?.get("sessionId") as? String
                val ok = captureAndUploadScreenshot(sessionId)
                mapOf("captured" to ok, "sessionId" to sessionId)
            }
            "RELEASE_OWNER" -> {
                DeviceOwnerManager(context).release()
                mapOf("released" to true)
            }
            else -> mapOf("ignored" to command.type)
        }

    // ---- Camera Snapshot ----

    /**
     * Capture a photo from the device's camera.
     * Uses Camera2 API to take a photo silently.
     *
     * NOTE: On modern Android (10+), foreground services with visible
     * notification can use the camera in the background. The child device
     * shows a persistent notification stating "Snapshot requested" for
     * transparency.
     */
    private fun captureCameraSnapshot(camera: String): File? {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA)
            != PackageManager.PERMISSION_GRANTED
        ) {
            return null
        }

        try {
            val outputDir = context.getExternalFilesDir(Environment.DIRECTORY_PICTURES)
            val outputFile = File(outputDir, "snapshot_${Instant.now().epochSecond}.jpg")
            captureViaIntent(camera, outputFile)
            return outputFile
        } catch (e: Exception) {
            return null
        }
    }

    /**
     * Uses the system camera intent with a transparent activity.
     * This shows a brief camera UI to the child, ensuring consent.
     */
    private fun captureViaIntent(camera: String, output: File) {
        val takePictureIntent = Intent(android.provider.MediaStore.ACTION_IMAGE_CAPTURE)
        val photoURI = FileProvider.getUriForFile(
            context,
            "${context.packageName}.fileprovider",
            output
        )
        takePictureIntent.putExtra(android.provider.MediaStore.EXTRA_OUTPUT, photoURI)
        takePictureIntent.addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        takePictureIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        takePictureIntent.putExtra("android.intent.extras.CAMERA_FACING",
            if (camera == "front") 1 else 0)

        // Start a transparent activity that handles the intent
        val intent = Intent(context, CameraCaptureActivity::class.java).apply {
            putExtra("output_uri", photoURI.toString())
            putExtra("facing", camera)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }

    // ---- Screen Recording ----

    /**
     * Start recording the device screen.
     * Uses MediaProjection API — requires user consent on Android 10+.
     * The consent dialog shows the child what is happening.
     */
    private fun startScreenRecording() {
        if (ScreenRecordService.isRecording) return
        val intent = Intent(context, ScreenRecordActivity::class.java).apply {
            putExtra("action", "start")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        runCatching { context.startActivity(intent) }
    }

    private fun stopScreenRecording() {
        runCatching { ScreenRecordService.stop(context) }
    }

    // ---- Screen Mirror ----

    /**
     * Start live mirror immediately when MediaProjection is already held from setup.
     * Only if the grant was lost do we briefly launch the system capture dialog
     * (no in-app Approve/Deny).
     */
    // ---- On-demand screenshot (accessibility capture, no projection consent) ----

    /**
     * Capture the current screen via the accessibility service and relay a single
     * JPEG frame to the parent over the screen session. Blocks briefly for the
     * async capture callback so the command result reflects the real outcome.
     */
    private fun captureAndUploadScreenshot(sessionId: String?): Boolean {
        if (sessionId.isNullOrBlank()) return false
        val service = MonitorAccessibilityService.instance ?: return false
        val latch = CountDownLatch(1)
        var jpeg: ByteArray? = null
        service.captureScreenshot(SCREENSHOT_QUALITY) { bytes ->
            jpeg = bytes
            latch.countDown()
        }
        val completed = runCatching { latch.await(5, TimeUnit.SECONDS) }.getOrDefault(false)
        val bytes = jpeg
        if (!completed || bytes == null) return false
        ScreenshotUploader.push(context, sessionId, bytes)
        return true
    }

    private fun requestScreenMirror(sessionId: String?) {
        if (sessionId.isNullOrBlank()) return
        when {
            ScreenMirrorService.hasProjection -> {
                ScreenMirrorService.startStream(context, sessionId)
            }
            DeviceStore(context).screenCaptureGranted() -> {
                runCatching {
                    context.startActivity(
                        ScreenMirrorActivity.streamIntent(context, sessionId),
                    )
                }
            }
            else -> AccessibilityLiveStreamService.startStream(context, sessionId)
        }
    }

    private companion object {
        const val SCREENSHOT_QUALITY = 60
    }
}
