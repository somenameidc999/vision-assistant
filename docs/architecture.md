# Architecture

Updated: 2026-11-06.
Status: backend exercised with real OpenRouter requests; native app built and launched in Simulator; the scene-question UI test passed. Live voice and physical camera checks remain pending.

## Data flow

```text
Rear or front camera -> local 1 fps frame buffer (30 seconds)
                                                    |
Microphone -> voice processing -> speech detection -> recorded question
                                                    |
                           latest + up to 5 older frames
                                                    |
                         authenticated local Mac backend
                                                    |
              8-turn text context -> OpenRouter Responses API
                                                    |
                             JSON transcript + answer
                                                    |
                     iOS transcript + local spoken reply
```

## App

SwiftUI owns the foreground session state and user controls. The active camera fills the screen behind compact transcript and control overlays. A shared frame-source interface provides AVFoundation rear- or front-camera capture. Only Debug Simulator builds can explicitly select the AVPlayer development scene with `--dev-prerecorded-scene`. Camera errors never select a video. The newest selected frame must be fresh. Each question requests an immediate frame after cancellation finishes, preserves millisecond timestamps, and aligns device timestamps to the backend clock. One stale validation rejection can retry with another fresh frame; accepted model requests are never replayed automatically. Source changes, playback rewinds, and video loops clear the visual history and invalidate pending answers.

The idle screen contains one centered camera icon button. Long-press opens Connection settings. Active sessions show icon controls for mute, stop speaking, camera switching, and end. Sampling counts, sampling explanations, and request metrics are absent from the demo interface. Scene sampling and budget measurements still operate internally.

Camera input changes run on the capture queue. A failed change retains the previous input. Switching cancels the current answer and clears local visual history. Source identifiers and capture timestamps reject frames queued before a change. Submission waits for a fresh frame from the new camera. The capture and preview use Apple's rotation coordinator on iOS 17 or later and portrait orientation on iOS 16.6. Both paths use matching unmirrored views. Physical orientation and camera switching remain unverified. [Apple rotation coordinator](https://developer.apple.com/documentation/avfoundation/avcapturedevice/rotationcoordinator), checked 2026-11-06.

The app supports iOS 16.6 or later. Apple Speech provides partial English words using `requiresOnDeviceRecognition = true` only after confirming on-device support and permission. A 300 ms prebuffer preserves the first word. Partial text stays local and is replaced by the model's returned transcript; the question's audio still goes to OpenRouter after speech ends. End, mute, and camera changes cancel partial recognition. Recognition failure leaves the original audio question path available. Microphone permission uses `AVAudioApplication` on iOS 17 or later and `AVAudioSession` on iOS 16.6.

The audio session requests one input channel after activation, before creating input I/O. This fixed a measured Core Audio abort on the development Mac’s virtual microphone route. The speech detector operates on mono 16 kHz samples after voice processing. It calibrates during the first second, retains a 300 ms prebuffer, requires sustained onset, ends after 700 ms of silence, and caps a question at 20 seconds. The app sends a canonical PCM16 WAV.

Apple speech synthesis produces owned copies of audio buffers, which convert to a fixed 48 kHz format and play through the same audio engine used for voice processing. The synthesizer does not manage the app’s capture session. The renderer resumes after synthesis session reconfiguration, and completion waits for both synthesis completion and queued audio buffers to finish. A new speech onset stops playback and cancels the previous turn. Callback generations prevent stale answers or audio buffers from restarting a stopped session. Voice processing failure leaves text questions available; it does not silently claim hands-free support.

Ending clears local scene and transcript content before asynchronous backend cleanup. Local preferences retain only the pending backend session UUID per endpoint so a relaunch can clean up an interrupted session. They never contain conversation text or credentials. Backgrounding pauses the session and requires explicit resume. Internal playback-scheduled timing is an approximation, not a first-audible-answer measurement.

## Backend

Fastify validates request sizes, JPEG dimensions, canonical audio, scene timestamps, authentication, and session state. Only one model request runs per session. Cancellations tombstone turn identifiers, including when the cancellation arrives before the question. Late or cancelled replies do not enter conversation history. The backend retains only eight text exchanges, and session content expires after 15 idle minutes.

The OpenRouter adapter submits a system instruction, text conversation history, timestamped images, and the recorded question. Image instructions are scene content. The response uses a strict JSON schema and a 512-token output cap. The adapter supports the two explicitly selected models, with no automatic model substitution.

The backend and experiments share one persistent spending ledger under ignored `runs/`. A process lock prevents concurrent writers. Each request reserves $0.25. Reported cost replaces the reservation. Uncertain charges stay reserved. Model inputs and price ceilings are checked before requests start. These controls are an application allowance, not a limit on other uses of the shared credential.

## Data and network

The OpenRouter credential stays in ignored root `.env`. The app receives a random local session token through ignored build configuration. The default listener is localhost:18787. A later iPhone demo can use the Mac's `.local` hostname on a trusted LAN, with local-network permission.

Frames, audio, and conversation text stay in memory by default. Backend logs contain only model, turn identifier, timing, frame count, and token/cost usage. Raw outputs from deliberately selected public-fixture experiments stay in ignored `runs/`. No application capture is saved to the photo library.

Provider training and retention policies are separate from application storage. See [OpenRouter findings](research/openrouter.md). The [API contract](api.md) defines the local interface. The [demo checklist](demo.md) defines unverified behavior.

The client also accepts private Tailscale HTTPS hostnames ending in `.ts.net`. Client-only bootstrap does not require a provider credential. The private Serve proxy is enabled on HTTPS port 8443. Mac-side health and authenticated session requests passed. No phone-side or cross-machine request has been measured yet.

## iPhone findings

Personal Team signing and physical installation passed on iPhone 12 / iOS 16.6.1. The user confirmed the live camera, spoken interaction, live words, and full-screen interface. An initial audio-route handler ended sessions on routine route notifications. Capture now starts on the main actor, checks settled input format after a short debounce, and restarts a stopped engine when the microphone format remains valid. Real interruptions still require explicit resume.

The current phone route uses an authenticated private-LAN proxy to the localhost backend. Private IPv4 ranges are explicitly validated; broad public-IP URLs are rejected. Debug builds retain only a numeric microphone-health snapshot under app Caches and log numeric recognition diagnostics. No audio, images, or recognized words enter those diagnostics. Formal performance, echo, and interruption targets remain unmeasured.
