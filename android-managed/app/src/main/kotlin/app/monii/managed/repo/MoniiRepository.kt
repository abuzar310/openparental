package app.monii.managed.repo

import android.content.Context
import android.os.Build
import app.monii.managed.data.ContentBuffer
import app.monii.managed.data.EventBuffer
import app.monii.managed.identity.DeviceStore
import app.monii.managed.net.ApiProvider
import app.monii.managed.net.ClaimRequest
import app.monii.managed.net.ClaimResponse
import app.monii.managed.net.CommandDto
import app.monii.managed.net.CommandResultRequest
import app.monii.managed.net.ConsentSessionRequest
import app.monii.managed.net.ContentItemDto
import app.monii.managed.net.EventInputDto
import app.monii.managed.net.HeartbeatRequest
import app.monii.managed.net.IngestContentRequest
import app.monii.managed.net.IngestPhotoFlagsRequest
import app.monii.managed.net.PhotoFlagItemDto
import app.monii.managed.net.IngestEventsRequest
import app.monii.managed.net.GeofenceDto
import app.monii.managed.net.GeofenceTransitionRequest
import app.monii.managed.net.LocationRequest
import app.monii.managed.net.ReauthRequest
import app.monii.managed.net.RequestUnblockRequest
import app.monii.managed.net.SelfUpdateRequest
import app.monii.managed.net.TamperRequest
import app.monii.managed.net.UploadFrameRequest
import retrofit2.HttpException
import java.time.Instant

/**
 * The device's single conversation point with the backend. Every authenticated
 * call goes through withReauth(): on a 401 it re-mints the device token from the
 * stored secret and retries once, so a token expiry is invisible to callers.
 */
class MoniiRepository(
    private val context: Context,
    private val store: DeviceStore,
) {
    private val api get() = ApiProvider.api(store)
    private val buffer = EventBuffer(context)

    suspend fun claim(baseUrl: String, code: String): ClaimResponse {
        store.setBaseUrl(baseUrl)
        val res = api.claim(
            ClaimRequest(
                token = code.trim(),
                deviceName = "${Build.MANUFACTURER} ${Build.MODEL}",
                manufacturer = Build.MANUFACTURER,
                model = Build.MODEL,
                osVersion = Build.VERSION.RELEASE,
                appVersion = APP_VERSION,
                fcmToken = store.fcmToken(),
            ),
        )
        store.savePairing(res.deviceId, res.deviceToken, res.deviceSecret)
        return res
    }

    suspend fun heartbeat(batteryPct: Int?) = withReauth {
        api.heartbeat(HeartbeatRequest(batteryPct))
    }

    /** Push the FCM token up once it's known (and after any rotation). */
    suspend fun syncFcmToken() {
        if (!store.fcmNeedsSync()) return
        val token = store.fcmToken() ?: return
        withReauth {
            api.selfUpdate(
                SelfUpdateRequest(
                    batteryPct = null,
                    osVersion = null,
                    appVersion = null,
                    fcmToken = token,
                ),
            )
        }
        store.markFcmSynced()
    }

    suspend fun pullCommands(): List<CommandDto> = withReauth { api.pendingCommands() }

    suspend fun ack(id: String) = withReauth { api.ackCommand(id) }

    suspend fun result(id: String, result: Map<String, Any?>?, error: String?) =
        withReauth { api.commandResult(id, CommandResultRequest(result, error)) }

    suspend fun reportTamper(kind: String, detail: String?) =
        withReauth { api.reportTamper(TamperRequest(kind, detail)) }

    suspend fun requestUnblock(appPackage: String?, reason: String?) =
        withReauth {
            api.requestUnblock(RequestUnblockRequest(appPackage, reason))
        }

    suspend fun reportLocation(lat: Double, lng: Double, accuracyM: Double?) =
        withReauth { api.reportLocation(LocationRequest(lat, lng, accuracyM)) }

    suspend fun listGeofences(): List<GeofenceDto> = withReauth { api.listGeofences() }

    suspend fun reportGeofenceTransition(geofenceId: String, transition: String) =
        withReauth {
            api.reportGeofenceTransition(
                GeofenceTransitionRequest(geofenceId, transition),
            )
        }

    suspend fun consentScreenSession(sessionId: String, approved: Boolean) =
        withReauth { api.consentScreenSession(sessionId, ConsentSessionRequest(approved)) }

    suspend fun stopScreenSession(sessionId: String) =
        withReauth { api.stopScreenSession(sessionId) }

    suspend fun uploadScreenFrame(sessionId: String, base64Jpeg: String) =
        withReauth { api.uploadScreenFrame(sessionId, UploadFrameRequest(base64Jpeg)) }

    suspend fun ingestPhotoFlags(items: List<PhotoFlagItemDto>) {
        if (items.isEmpty()) return
        withReauth { api.ingestPhotoFlags(IngestPhotoFlagsRequest(items)) }
    }

    fun bufferEvent(type: String, data: Map<String, Any?>) {
        buffer.add(EventInputDto(type, data, Instant.now().toString()))
    }

    /** Buffer a content item for keyword / browser / social history. */
    fun bufferContent(item: ContentItemDto) {
        ContentBuffer.add(context, item)
    }

    suspend fun flushEvents() {
        val items = buffer.drainAndClear()
        if (items.isEmpty()) return
        try {
            withReauth { api.ingestEvents(IngestEventsRequest(items)) }
        } catch (e: Exception) {
            buffer.readd(items)
            throw e
        }
    }

    suspend fun ingestContentDirect(item: ContentItemDto) {
        withReauth { api.ingestContent(IngestContentRequest(listOf(item))) }
    }

    /** Flush buffered content items (keyword detections) to POST /content. */
    suspend fun flushContent() {
        val raw = ContentBuffer.drainAndClear(context)
        if (raw.isEmpty()) return
        val items = raw.mapNotNull { e ->
            val d = e.data
            if (d["source"] == null) return@mapNotNull null
            ContentItemDto(
                source = d["source"] as? String ?: "",
                body = d["body"] as? String ?: "",
                matched = d["matched"] as? String,
                counterparty = d["counterparty"] as? String,
                occurredAt = d["occurredAt"] as? String ?: return@mapNotNull null,
            )
        }
        if (items.isEmpty()) return
        try {
            withReauth { api.ingestContent(IngestContentRequest(items)) }
        } catch (e: Exception) {
            ContentBuffer.readd(context, raw)
            throw e
        }
    }

    private suspend fun <T> withReauth(block: suspend () -> T): T =
        try {
            block()
        } catch (e: HttpException) {
            val id = store.deviceId()
            val secret = store.deviceSecret()
            if (e.code() == 401 && id != null && secret != null) {
                val r = api.reauth(ReauthRequest(id, secret))
                store.setToken(r.deviceToken)
                block()
            } else {
                throw e
            }
        }

    companion object {
        const val APP_VERSION = "0.0.1"
    }
}
