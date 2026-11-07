# Demonstration and validation

Status: physical installation passed on iPhone 12 / iOS 16.6.1. The user confirmed live camera use, spoken interaction, live words, and the full-screen interface. Native build and the text-question Simulator UI test also passed on iPhone 17 Pro / iOS 26.5. The audio engine starts after requesting mono input, and isolated playback completion passes with microphone analysis muted. The user reports no microphone on this Mac, so live spoken input and audible-output verification remain pending. Unchecked items below are acceptance checks, not measured success.

## iPhone demo sequence

1. Start the Mac backend.
2. Open the installed iPhone app.
3. Tap the centered camera icon button.
4. Allow camera and microphone access.
5. Point the rear camera at a non-sensitive ordinary scene.
6. Wait quietly for one second.
7. Ask “What do you see?”
8. Ask a follow-up question.
9. Tap the camera-switch icon to select the front camera.
10. Ask about the new view.
11. Speak a new question while the assistant answers.
12. Tap the stop icon to end the session.

The controls are mute, stop speaking, switch camera, and end, from left to right. Stop speaking is disabled until the assistant starts speaking. Each icon has an accessibility label. Long-press the centered start button for Connection settings. A failed camera request shows an error and never substitutes a video.

## Simulator development sequence

Run `./scripts/run_simulator.sh --dev-prerecorded-scene` for the explicit Debug development scene. Start with the centered camera button. The active screen must show **DEVELOPMENT VIDEO**. Camera switching is disabled because no physical camera exists in this mode. A normal launch without the flag requests a real camera and shows an unavailable-camera error in Simulator.

Ask “What color is the cup?” The development video shifts the photograph at 15 seconds and changes TABLE 42 to TABLE 17 at 25 seconds. Ask “What changed?” after each change. The video loops at 40 seconds and clears visual history. The photograph shifts on a canvas; do not describe the shift as physical cup movement. The assistant has only sampled views and may miss brief events. Development video is excluded from the iPhone executable and from Release executables.

## Simulator acceptance record

- [x] Build and launch with Xcode and an iOS 26 runtime.
- [ ] Verify microphone audio from the selected Mac input reaches the app.
- [ ] Verify spoken output from the selected Mac output is audible.
- [ ] Complete 20 actual spoken questions and record speech-end-to-first-audible-answer delay.
- [ ] Measure median delay at or below five seconds and 95th-percentile delay at or below ten seconds.
- [ ] Interrupt ten answers; at least nine stop within 500 ms of new speech.
- [ ] Run a ten-minute conversation with no question triggered by assistant playback.
- [ ] Confirm a fresh frame accompanies each question.
- [ ] Confirm loop/reset clears scene history and invalidates in-flight answers.
- [ ] Deny microphone access and verify useful text questions remain possible.
- [ ] Disconnect the backend and verify a recoverable error.
- [ ] Background the app and verify capture stops without automatic resume.
- [ ] End a pending question and confirm no late answer restarts playback.
- [x] Confirm ending clears local transcript and frame history.

The app’s playback-scheduled timing is approximate. Use recorded loopback audio with known speech endpoints for audible-delay and interruption measurements. Do not score an injected WAV as live microphone evidence. Keep recordings local under ignored `runs/` and publish only sanitized timings.

## Physical iPhone acceptance record

- [x] Install with Personal Team signing.
- [x] Confirm full-screen camera and live words on the user's iPhone (user report).
- [x] Confirm microphone, camera, and local-network permissions are enabled (user photo).
- [ ] Verify front and rear camera preview and uploaded frame orientation in portrait.
- [ ] Switch cameras during an answer; confirm playback stops and old-view frames cannot answer the next question.
- [ ] Verify a failed camera switch retains the previous camera.
- [ ] Verify camera and microphone denial behavior.
- [ ] Verify local-network connection to the Mac.
- [ ] Verify speaker feedback, voice interruption, and route changes.
- [ ] Run ten minutes and record battery, heat, frame age, delay, and cost.

The physical checks above distinguish user confirmation from measured acceptance targets. Physical checks do not block the first simulator delivery. Simulator checks still block calling the first delivery complete.

Repeat the actual UI check with `./scripts/test_simulator.sh` while the backend runs. The test verifies a visible scene answer, isolated playback completion with microphone analysis muted, and session cleanup. It does not inject microphone audio and does not establish audible speech, real voice interruption, or the ten-minute feedback target. See the [Simulator experiment](../experiments/2026-11-06-simulator.md).
