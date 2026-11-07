# Decision log

## 2026-11-06 — Publish the source

Generate the Xcode project locally from `ios/project.yml` so signing settings stay on the development Mac. Keep credentials, captures, and device diagnostics in ignored local paths. Use the GitHub commit address for the public history.

Bind the backend to loopback. Connect other devices through the existing private proxies. The iOS client rejects HTTP redirects so a configured backend cannot forward camera or microphone payloads to a second destination.

## 2026-11-05 — Start with a research repo

Status: accepted direction.

The user wants to explore, research, and eventually build an assistant with vision.
The initial repo contains research and experiment plans.
Implementation follows evidence from small experiments.

## 2026-11-05 — Use the camera as the primary input

Status: confirmed by the user.

The user specified “whatever is on the camera it has.”
Research should support general camera scenes.
Camera hardware and device remain undecided.

## 2026-11-05 — Evaluate snapshots before streaming

Status: proposed sequence.

Snapshots allow the same visual input to be compared across approaches.
That comparison helps isolate model quality from streaming behavior.
Live performance needs a separate experiment.
No provider, model, programming language, or deployment platform is selected.

## 2026-11-06 — Deliver a native iOS simulator demo first

Status: confirmed by the user; implementation authorized.

Use SwiftUI and AVFoundation targeting iOS 26. The first delivery uses Simulator because no iPhone is connected. The prerecorded scene is clearly labeled. A separate rear-camera source prepares for later physical testing. An uncompiled source tree is not a completed simulator delivery.

## 2026-11-06 — Use OpenRouter through a local Mac backend

Status: confirmed by the user.

Use TypeScript, Node.js 22, and Fastify. The Mac holds the provider credential. No public hosting, new provider account, or GitHub remote is required. The local demo listener uses port 18787 because 8787 was already occupied. Do not alter the unrelated listener.

Default model: `google/gemini-3.8-flash`. Compare `google/gemini-3.5-flash-lite` without automatically promoting it. Actual combined speech/image requests passed for both. Cloud Vision and a direct Gemini Live connection are deferred.

## 2026-11-06 — Use sampled visual history and audio turns

Status: confirmed by the user; API feasibility measured, device behavior unverified.

The app samples at 1 fps, retains 30 seconds locally, and submits up to six frames with each recorded question. No background model requests run. The latest eight text exchanges support follow-ups. Voice processing, local speech detection, and Apple speech synthesis provide the proposed hands-free experience. Interruptions cancel older turns. Session end clears content.

## 2026-11-06 — Preserve a $10 validation allowance

Status: confirmed by the user.

Allocate $2 for feasibility and baseline work, $6 for integration, and $2 for final validation. Keep one shared persistent ledger and reserve conservative request costs. Keep uncertain charges reserved. Do not modify spending controls on the existing shared credential. Record provider-reported charges separately from estimates.

## 2026-11-06 — Distinguish source checks from simulator evidence

Status: implementation constraint observed.

Full Xcode was initially absent. The installer requested Apple Account sign-in. The user subsequently installed Xcode 26.6 files, but Apple license and simulator setup remain pending. Continue independent backend and source work while the user handles local setup. Native source parsing and executable Swift core checks do not prove an iOS build, microphone path, speaker path, feedback cancellation, or interruption timing. The first delivery remains incomplete until the simulator checklist passes.

## 2026-11-06 — Validate the native app in Simulator

Status: measured, limited to build, audio engine initialization, and the text-question UI flow.

Installed iOS 26.5 build 23F73. Xcode 26.6's preferred runtime mapping pointed at missing build 23F81a. A supported `simctl runtime match set iphoneos26.5 23F73` override made the installed runtime eligible. Native build and the Simulator UI test then ran.

The first UI run exposed a Core Audio initialization abort on the eight-channel Jump Desktop route. Requesting one input channel after audio-session activation fixed initialization. The next run exposed Swift UUID uppercase session paths, which did not match the backend's lowercase map keys. The client now serializes lowercase session paths and the backend accepts case-insensitive UUID paths. A backend regression test covers that boundary.

The final UI run submitted a scene question, received a real model reply, verified the reply was visible, and ended the session. Keyboard dismissal and scroll-to-reply were added after inspecting the first screenshot. Four XCTest core tests also passed. This evidence does not prove live voice conversation.

## 2026-11-06 — Prepare a separate Simulator client over Tailscale

Status: user direction; client preparation implemented, network setup deferred.

The user reports no microphone on this Mac and intends to use another machine connected through Tailscale. Keep the backend credential on this Mac. Add client-only bootstrap and accept private `.ts.net` HTTPS endpoints. Provide a source archive that excludes credentials and local captures. Configure and test a private Serve proxy only after the other machine is chosen. No Tailscale service was enabled.

## 2026-11-06 — Evaluate Astryx for the UI

Status: capability assessment; no Astryx package integrated.

The user asked whether [Astryx components](https://astryx.atmeta.com/components) can be used in the app. The [project homepage](https://astryx.atmeta.com/) lists React 19+ and StyleX. The existing app uses SwiftUI, so those web components cannot be imported directly. Recreating the visual patterns in native SwiftUI is the recommended approach. An Astryx redesign has not been implemented. Checked: 2026-11-06.

## 2026-11-06 — Verify output completion independently of live speech

Status: measured in Simulator with microphone analysis muted.

A strict playback-completion assertion exposed that synthesis session changes stopped the render engine. The speech adapter now uses fixed-format buffer conversion, owns each buffer before asynchronous scheduling, separates synthesis session management, resumes rendering when necessary, and tracks actual buffer completion. The final UI run reached the dedicated completion callback and passed. This is not proof of live microphone capture, audible output heard by a person, echo cancellation, or interruption behavior. Those checks remain pending on another suitable machine.

## 2026-11-06 — Prepare installation on the user's iPhone

Status: user-authorized device installation; local pairing and signing pending.

The user selected this Mac mini for the first USB installation. An unsigned native iPhone build succeeded. Xcode initially found no paired phone and the keychain had no valid development signing identity. Local Apple Account sign-in and Personal Team selection remain user setup steps. The app has not been installed or run on an iPhone yet.

Enabled private Tailscale Serve on HTTPS port 8443, proxying only to the existing localhost backend on port 18787. The prior Serve configuration was empty. Read-back confirmed public Funnel is disabled. Health returned 200, authenticated session creation returned 201, and session deletion returned 204 through the private HTTPS endpoint from the Mac. This does not prove the iPhone's network connection.

The iPhone backend URL is stored only in ignored configuration. The deployment helper refuses localhost for a phone, uses Xcode's locally stored Apple Account for provisioning, scopes the app identifier to the selected development team, and checks the signature before installation. Device identifiers and build outputs remain under ignored runs/. No Apple password or OpenRouter credential is requested by the helper.

## 2026-11-06 — Use live cameras for the actual demo

Status: user direction; implementation added; physical verification pending.

The user requires live front or rear device cameras for the actual demo. Prerecorded scenes remain development fixtures only. A camera failure must show an error, never silently substitute a video. The fixture source and player compile only for Debug Simulator builds and require the explicit `--dev-prerecorded-scene` launch argument. The normal Simulator launch reports that a camera is unavailable.

Replace the idle page with one centered camera icon button. Keep Connection settings in its long-press menu. Use icon-only mute, stop-speaking, camera-switch, and end controls during sessions, with accessibility labels. Remove visible frame counts, evidence captions, sampling explanations, and request metrics. Retain internal frame selection, observation-gap instructions, and sanitized budget measurements.

Switching camera cancels pending requests and speech, clears scene history, and waits for a fresh frame. Input changes run on one serial capture queue and restore the old input if the new input cannot be added. Reject callbacks from old source identifiers and sample timestamps preceding the input change. Preview and uploaded images use matching unmirrored views and Apple's rotation coordinator. iPhone camera behavior remains a physical acceptance check.

## 2026-11-06 — Support the connected iPhone on iOS 16.6.1

Status: compatibility build passed; signing and physical execution pending.

Xcode detected the user's iPhone 12 over USB running iOS 16.6.1. The original iOS 26 deployment target excluded that phone. Lower the minimum deployment target to iOS 16.6 for both the app and VisionCore. Retain the existing camera and voice behavior. Use availability guards for microphone permission and camera rotation APIs introduced in iOS 17. Use AVFoundation portrait orientation on iOS 16.6 and matching unmirrored preview and capture. The phone's operating system is unchanged.

CoreDevice reported the older phone as unsupported and did not expose its operating system version. `xcdevice` returned the phone version and a Developer Mode requirement. Use `xcdevice` for device discovery, reject unknown or incompatible versions, and use `ios-deploy` for installation and launch before iOS 17. Continue using `devicectl` on newer phones. Installed `ios-deploy` 1.12.2 locally. Installer regression checks cover legacy discovery, simulator exclusion, minimum-version checks, and Developer Mode errors.

The unsigned iPhone compatibility build passed and its Info.plist reports `MinimumOSVersion` 16.6. No device build has been installed yet. Apple Account sign-in, Personal Team selection, and device readiness remain local setup steps. No credential or personal capture enters source control.

Sources checked 2026-11-06: [Apple Xcode requirements](https://developer.apple.com/xcode/system-requirements), [ios-deploy](https://github.com/ios-control/ios-deploy), [Apple Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device). API availability also checked in the installed iOS SDK headers.

## 2026-11-06 — Choose the white and blue app icon

Status: selected by the user; app asset configured.

Use the approved speaking-head silhouette with three sound rays in blue on a white background. The sample was made with the built-in image-generation tool. The final color-edit prompt preserved the silhouette and changed only the background to white and the head and rays to blue. Store the opaque 1024×1024 PNG in `ios/VisionAssistant/Assets.xcassets/AppIcon.appiconset/AppIcon.png`. Set `ASSETCATALOG_COMPILER_APPICON_NAME` to `AppIcon` in the XcodeGen specification. A new app build and installation applies the icon to the iPhone.

## 2026-11-06 — Complete physical installation and recover session startup

Status: signed installation and launch verified; live behavior user-confirmed.

Selected the user's Personal Team through macOS accessibility automation in Xcode. The free development signature and device provisioning checks passed. The user trusted the developer certificate on the iPhone. `ios-deploy` installed the app, but its LLDB `safequit` path did not reliably keep the process running. Use `ios-deploy` for installation and `idevicedebug --detach` for launch on iOS 16; verify a live process afterward. The modern path retains `devicectl`.

The phone could not resolve the configured Tailscale hostname. Added an authenticated, in-memory proxy bound to the Mac's specific private Wi-Fi address. Keep the backend on localhost and preserve the optional private Tailscale HTTPS route. Direct IPv4 URLs are restricted to RFC 1918 ranges. The app declares bounded private-network ATS exceptions. Setup health, unauthorized, authenticated session, and deletion checks passed through the LAN route.

Routine audio-route notifications initially ended the session. Start capture on the main actor, debounce routine route checks, retain capture if the input format is valid, and restart a stopped engine. Preserve explicit resume for real interruptions and changed microphone formats. Debug diagnostics contain numeric input levels and recognition status, never recordings or words.

App reinstalls left backend sessions open and reached the four-session limit. Cleared this demo's stale in-memory sessions by restarting its backend; preserved the spending ledger. Persist only a pending session UUID per endpoint, then delete that session before a new start after relaunch. Successful cleanup clears its record; late cleanup cannot erase a newer session's record.

## 2026-11-06 — Show live words over a full-screen camera

Status: compiled, Simulator-checked, installed, and confirmed by the user on iPhone.

The user requested live words, a larger camera experience, and recovery from intermittent stale-view errors. Make the camera fill the screen behind compact transcript and icon-control overlays. Use Apple Speech for on-device English partial recognition after explicit Speech Recognition permission and a capability check. Do not enable server-based Speech fallback. Keep partial words local; continue sending the completed audio question to OpenRouter. The model's returned transcript replaces the local preview.

Preserve fractional capture seconds during JSON encoding and align capture times to the backend clock using session-creation timing. Acquire a fresh frame after cancellation finishes. A stale validation rejection may refresh and retry once because rejection occurs before budget reservation and turn admission. Never replay a request that may already have reached the model. Retain the two-second freshness requirement.

The physical user reported that the new full-screen view and live words look good. Sanitized recognition diagnostics showed partial and final results. Formal latency percentiles, ten-minute feedback behavior, and interruption trials remain pending.

Sources checked 2026-11-06: [Apple live audio recognition](https://developer.apple.com/documentation/speech/recognizing-speech-in-live-audio), [on-device recognition](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition), [local-network ATS policy](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking), [libimobiledevice tools](https://github.com/libimobiledevice/libimobiledevice).
