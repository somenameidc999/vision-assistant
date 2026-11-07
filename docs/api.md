# Local backend API

Protocol version: 1. The backend binds to `127.0.0.1:18787` by default. All endpoints except health require `Authorization: Bearer <SESSION_TOKEN>`. No OpenRouter credential crosses this interface.

| Method | Path | Behavior |
| --- | --- | --- |
| GET | `/health` | Returns service status and `protocolVersion`. |
| POST | `/v1/sessions` | Creates a session; returns `sessionId`, millisecond ISO 8601 `serverTime`, and budget accounting. No request body is required. |
| POST | `/v1/sessions/:id/turns` | Submits a question and frames; returns a completed response. |
| POST | `/v1/sessions/:id/cancel` | Accepts `turnId`; aborts a pending turn or marks a delivered answer interrupted. |
| DELETE | `/v1/sessions/:id` | Aborts active work and discards session content. Idempotent. |

## Question request

Session UUID paths accept either letter case, including Swift’s uppercase UUID formatting. `turnId` is a new UUID for each submission. Supply exactly one of `text` or `audio`. `audio` contains `format: "wav"` and base64 `data`. WAV input must use the canonical 44-byte PCM header, mono 16 kHz, 16-bit samples, and at most 20 seconds. The Swift core creates this format.

`frames` contains one to six entries. Each entry has a UUID `id`, UUID `sourceId`, ISO 8601 `capturedAt`, optional `playbackSeconds`, and base64 `jpeg`. JPEG dimensions are at most 1024 pixels on either edge, with at most 300 KB per frame. All frames belong to one source. The newest capture must be at most two seconds old at backend receipt. The app preserves fractional seconds and aligns capture times to the server using the session-creation round trip. It fetches a fresh frame after cancellation completes and retries one `stale_frame` rejection before any model charge. The history window allows a two-second transport margin around the app’s 30-second window.

Requests are limited to 6 MB. Text questions are limited to 2,000 characters. Oldest-to-newest frame order is established by the adapter. Only the last eight text exchanges enter model context. Images and audio do not persist in conversation history.

## Question response

Responses include `turnId`, `transcript`, `answer`, `model`, `providerResponseId`, `usage`, frame metadata without JPEG data, `timing`, and `budget`.

`usage.costUSD` is the provider-reported charge when available. A null charge leaves the reservation intact. `timing.providerMs` measures the backend model call. `newestFrameAgeAtResponseMs` identifies how old the latest evidence is when the backend responds. Neither value measures first audible speech at the device.

Errors have `{ "error": { "code": "...", "message": "..." } }`. Recoverable cases include invalid input (400/422), authentication (401), budget exhaustion (402), expired session (404), duplicate or cancelled turn (409), rate limiting (429), and provider failure or timeout (502/504).

## Lifecycle

One turn runs per session. The app cancels an older turn before submitting a replacement. Reusing an accepted turn UUID is rejected. Validation failures before admission, including `stale_frame`, do not consume a turn UUID or reserve budget. Late answers cannot modify cancelled or deleted sessions. Idle sessions expire after 15 minutes; at most four sessions exist concurrently.

Ending a session stops local capture before network cleanup. The app keeps only the last backend session identifier per endpoint in local preferences and deletes that session before creating a replacement after app relaunch. Successful cleanup clears the identifier; failed cleanup stays available for retry. Cancelling a request cannot guarantee cancellation of provider billing. Uncertain charges remain reserved.
