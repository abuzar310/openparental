package app.monii.managed.mirror

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Parcelable
import android.util.Base64
import android.util.DisplayMetrics
import android.util.Log
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import app.monii.managed.R
import app.monii.managed.identity.DeviceStore
import app.monii.managed.repo.MoniiRepository
import io.socket.client.IO
import io.socket.client.Socket
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.net.URI
import kotlin.math.roundToInt

/**
 * Holds MediaProjection after a one-time system grant (onboarding), then streams
 * when the parent starts a session. Child-facing UI stays generic so viewing
 * does not announce itself in our app.
 */
class ScreenMirrorService : Service() {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var sessionId: String = ""
    private var projection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var socket: Socket? = null
    private var captureThread: HandlerThread? = null
    private var captureHandler: Handler? = null
    private var lastEmitAt = 0L
    private var streaming = false

    private val projectionCallback = object : MediaProjection.Callback() {
        override fun onStop() {
            Log.w(TAG, "MediaProjection stopped by system")
            stopStreamOnly()
            projection = null
            hasProjection = false
            DeviceStore(this@ScreenMirrorService).setScreenCaptureGranted(false)
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP_ALL -> {
                fullTeardown()
                return START_NOT_STICKY
            }
            ACTION_STOP_STREAM -> {
                stopStreamOnly(endSession = true)
                updateIdleNotification()
                return START_STICKY
            }
            ACTION_BIND_PROJECTION -> {
                bindProjection(intent)
                return START_STICKY
            }
            ACTION_START_STREAM -> {
                val sid = intent.getStringExtra(EXTRA_SESSION_ID).orEmpty()
                if (sid.isBlank()) return START_STICKY
                startStream(sid)
                return START_STICKY
            }
            else -> {
                // Legacy start path: bind + stream in one shot
                val sid = intent?.getStringExtra(EXTRA_SESSION_ID).orEmpty()
                val resultCode = intent?.getIntExtra(EXTRA_RESULT_CODE, 0) ?: 0
                val data = intent?.parcelableExtra<Intent>(EXTRA_DATA)
                if (sid.isNotBlank() && data != null && resultCode != 0) {
                    bindProjection(resultCode, data)
                    startStream(sid)
                }
                return START_STICKY
            }
        }
    }

    private fun bindProjection(intent: Intent) {
        val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, 0)
        val data = intent.parcelableExtra<Intent>(EXTRA_DATA) ?: return
        if (resultCode == 0) return
        bindProjection(resultCode, data)
    }

    private fun bindProjection(resultCode: Int, data: Intent) {
        startForegroundCompat()
        if (projection != null) return
        val mpm = getSystemService(MediaProjectionManager::class.java)
        projection = mpm.getMediaProjection(resultCode, data)?.also {
            it.registerCallback(projectionCallback, Handler(mainLooper))
        }
        if (projection == null) {
            stopSelf()
            return
        }
        hasProjection = true
        DeviceStore(this).setScreenCaptureGranted(true)
        updateIdleNotification()
    }

    private fun startStream(sid: String) {
        val proj = projection
        if (proj == null) {
            Log.w(TAG, "No MediaProjection — need setup grant")
            return
        }
        sessionId = sid
        streaming = true
        // Keep the same quiet notification — do not announce that viewing started.
        startForegroundCompat()
        connectSocketAndCapture()
    }

    private fun connectSocketAndCapture() {
        stopSocketAndCaptureSurfaces()
        val store = DeviceStore(this)
        val token = store.token()
        if (token == null) {
            stopStreamOnly(endSession = true)
            return
        }

        try {
            val base = store.baseUrl().trimEnd('/')
            val opts = IO.Options.builder()
                .setAuth(mapOf("token" to token))
                .setTransports(arrayOf("websocket", "polling"))
                .build()
            val sock = IO.socket(URI.create("$base/screen"), opts)
            socket = sock
            sock.on(Socket.EVENT_CONNECT) {
                sock.emit("join", JSONObject().put("sessionId", sessionId))
                startCapture()
            }
            sock.on("session_ended") {
                stopStreamOnly(endSession = false)
                updateIdleNotification()
            }
            sock.connect()
        } catch (e: Exception) {
            Log.e(TAG, "socket connect failed", e)
            stopStreamOnly(endSession = true)
        }
    }

    private fun startCapture() {
        val proj = projection ?: return
        val metrics = displayMetrics()
        val fullW = metrics.widthPixels
        val fullH = metrics.heightPixels
        val density = metrics.densityDpi
        val scale = TARGET_WIDTH.toFloat() / fullW.coerceAtLeast(1)
        val width = TARGET_WIDTH
        val height = (fullH * scale).roundToInt().coerceAtLeast(2)

        captureThread = HandlerThread("mirror-capture").also { it.start() }
        captureHandler = Handler(captureThread!!.looper)

        val reader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)
        imageReader = reader
        reader.setOnImageAvailableListener({ r ->
            val image = r.acquireLatestImage() ?: return@setOnImageAvailableListener
            try {
                val now = System.currentTimeMillis()
                if (now - lastEmitAt < FRAME_INTERVAL_MS) return@setOnImageAvailableListener
                lastEmitAt = now
                val plane = image.planes[0]
                val buffer = plane.buffer
                val pixelStride = plane.pixelStride
                val rowStride = plane.rowStride
                val rowPadding = rowStride - pixelStride * width
                val bitmap = Bitmap.createBitmap(
                    width + rowPadding / pixelStride,
                    height,
                    Bitmap.Config.ARGB_8888,
                )
                bitmap.copyPixelsFromBuffer(buffer)
                val cropped = if (bitmap.width == width) {
                    bitmap
                } else {
                    Bitmap.createBitmap(bitmap, 0, 0, width, height).also { bitmap.recycle() }
                }
                val baos = ByteArrayOutputStream()
                cropped.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, baos)
                cropped.recycle()
                val b64 = Base64.encodeToString(baos.toByteArray(), Base64.NO_WRAP)
                val sock = socket
                if (sock?.connected() == true) {
                    sock.emit(
                        "frame",
                        JSONObject()
                            .put("sessionId", sessionId)
                            .put("data", b64),
                    )
                }
            } catch (e: Exception) {
                Log.w(TAG, "frame encode failed: ${e.message}")
            } finally {
                image.close()
            }
        }, captureHandler)

        virtualDisplay = proj.createVirtualDisplay(
            "openparental-mirror",
            width,
            height,
            density,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            reader.surface,
            null,
            captureHandler,
        )
    }

    private fun displayMetrics(): DisplayMetrics {
        val metrics = DisplayMetrics()
        val wm = getSystemService(WindowManager::class.java)
        @Suppress("DEPRECATION")
        wm.defaultDisplay.getRealMetrics(metrics)
        return metrics
    }

    private fun stopStreamOnly(endSession: Boolean = true) {
        streaming = false
        if (endSession && sessionId.isNotBlank()) {
            val sid = sessionId
            scope.launch {
                runCatching {
                    MoniiRepository(this@ScreenMirrorService, DeviceStore(this@ScreenMirrorService))
                        .stopScreenSession(sid)
                }
            }
        }
        sessionId = ""
        stopSocketAndCaptureSurfaces()
    }

    private fun stopSocketAndCaptureSurfaces() {
        try {
            virtualDisplay?.release()
        } catch (_: Exception) {
        }
        virtualDisplay = null
        try {
            imageReader?.close()
        } catch (_: Exception) {
        }
        imageReader = null
        try {
            socket?.disconnect()
            socket?.off()
        } catch (_: Exception) {
        }
        socket = null
        captureThread?.quitSafely()
        captureThread = null
        captureHandler = null
    }

    private fun fullTeardown() {
        stopStreamOnly(endSession = true)
        try {
            projection?.unregisterCallback(projectionCallback)
            projection?.stop()
        } catch (_: Exception) {
        }
        projection = null
        hasProjection = false
        DeviceStore(this).setScreenCaptureGranted(false)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        stopSocketAndCaptureSurfaces()
        try {
            projection?.unregisterCallback(projectionCallback)
            projection?.stop()
        } catch (_: Exception) {
        }
        projection = null
        hasProjection = false
        scope.cancel()
        super.onDestroy()
    }

    private fun updateIdleNotification() {
        if (projection != null) {
            // Same generic notification whether idle or streaming — don't tip the child off.
            startForegroundCompat()
        }
    }

    private fun startForegroundCompat() {
        createChannel()
        // Generic quiet notification — same text whether idle or streaming.
        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.mirror_ready_title))
            .setContentText(getString(R.string.mirror_ready_text))
            .setSmallIcon(R.drawable.ic_launcher)
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()

        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(
                NOTIF_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION,
            )
        } else {
            startForeground(NOTIF_ID, notification)
        }
    }

    private fun createChannel() {
        val nm = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.fgs_title),
            NotificationManager.IMPORTANCE_MIN,
        ).apply {
            setShowBadge(false)
            setSound(null, null)
            enableVibration(false)
            description = getString(R.string.mirror_ready_text)
        }
        nm.createNotificationChannel(channel)
    }

    companion object {
        private const val TAG = "ScreenMirror"
        private const val CHANNEL_ID = "screen_mirror"
        private const val NOTIF_ID = 42
        private const val EXTRA_SESSION_ID = "session_id"
        private const val EXTRA_RESULT_CODE = "result_code"
        private const val EXTRA_DATA = "data"

        const val ACTION_BIND_PROJECTION = "app.monii.managed.BIND_PROJECTION"
        const val ACTION_START_STREAM = "app.monii.managed.START_STREAM"
        const val ACTION_STOP_STREAM = "app.monii.managed.STOP_STREAM"
        const val ACTION_STOP_ALL = "app.monii.managed.STOP_MIRROR"

        private const val TARGET_WIDTH = 1080
        private const val JPEG_QUALITY = 60
        private const val FRAME_INTERVAL_MS = 200L

        @Volatile
        var hasProjection: Boolean = false
            private set

        fun bindProjection(context: Context, resultCode: Int, data: Intent) {
            val intent = Intent(context, ScreenMirrorService::class.java).apply {
                action = ACTION_BIND_PROJECTION
                putExtra(EXTRA_RESULT_CODE, resultCode)
                putExtra(EXTRA_DATA, data)
            }
            context.startForegroundService(intent)
        }

        fun startStream(context: Context, sessionId: String) {
            val intent = Intent(context, ScreenMirrorService::class.java).apply {
                action = ACTION_START_STREAM
                putExtra(EXTRA_SESSION_ID, sessionId)
            }
            context.startForegroundService(intent)
        }

        /** One-shot: bind projection and start streaming in a single service start. */
        fun startWithProjection(
            context: Context,
            sessionId: String,
            resultCode: Int,
            data: Intent,
        ) {
            val intent = Intent(context, ScreenMirrorService::class.java).apply {
                putExtra(EXTRA_SESSION_ID, sessionId)
                putExtra(EXTRA_RESULT_CODE, resultCode)
                putExtra(EXTRA_DATA, data)
            }
            context.startForegroundService(intent)
        }
    }
}

private inline fun <reified T : Parcelable> Intent.parcelableExtra(key: String): T? =
    if (Build.VERSION.SDK_INT >= 33) {
        getParcelableExtra(key, T::class.java)
    } else {
        @Suppress("DEPRECATION")
        getParcelableExtra(key) as? T
    }
