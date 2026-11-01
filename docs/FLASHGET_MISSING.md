# FlashGet features still missing in OpenParental

Source of truth: [`research/flashget/reference/FEATURE_PARITY.json`](../research/flashget/reference/FEATURE_PARITY.json) (mined from decompile strings + layouts).

## Not implemented (real gaps)

| FlashGet module | What they have | What we need |
|-----------------|----------------|--------------|
| **WebRTC / LiteAV mirror** | HD screen + remote camera stream | Phase 2 transport; today a11y JPEG ~1fps |
| **Albums Safety (full)** | On-device ML + optional WiFi image download | We only send metadata `PhotoFlag`; no thumbnails |
| **Scheduled snapshots** | `ScreenSnapshot` / cron captures | **On** — policy `snapshotIntervalMinutes` + WorkManager |
| **Payment / ads / redeem** | Monetization | Out of scope (self-hosted) |

## Partial (works but weaker than FlashGet)

| Module | Gap |
|--------|-----|
| Remote camera | System camera intent + JPEG in content feed (not silent WebRTC) |
| Screen / ambient record | Uploaded to parent **Recordings** feed (~1.2MB cap per clip) |
| Keyword detection | Built-in lists + **custom keywords in policy**; no per-app picker UI |
| MQTT / FCM | Code present; needs env (`MQTT_URL`, FCM service account) |
| Live screen | No cast icon (a11y path); lower FPS vs FlashGet WebRTC |

## Shipped (decompile parity target met)

Bind/install flow, device hub sections, app rules tri-state, geofences, location history, usage/activity, SMS/calls/browser/notifications/social, tamper alerts, hide launcher, device owner path, kids installer module, AI usage report, HTTP live screen on Vercel.
