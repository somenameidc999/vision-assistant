# Experiment: native Simulator build and scene conversation

Date: 2026-11-06, America/Los_Angeles.
Status: native build, visible text-question UI flow, session cleanup, and isolated audio-engine playback completion passed. Live spoken input and audible-output confirmation remain unavailable.
Base commit: `40ae6ea`; implementation changes are uncommitted.

## Environment

- Mac: Apple silicon, macOS 26.5.2.
- Xcode: 26.6, build 17F113.
- Simulator: iPhone 17 Pro, iOS 26.5, build 23F73.
- SDK: canonical version 26.5; internal version metadata 26.5.1 / 23F81a.
- Backend: Node.js 22.22.3, TypeScript, Fastify, localhost port 18787.
- Scene: bundled CC0 coffee photograph animated as a clearly labeled prerecorded video.
- Provider: OpenRouter, `google/gemini-3.8-flash`, image questions through the actual native client.

## Reproduction

```sh
./scripts/run_backend.sh
./scripts/run_simulator.sh --dev-prerecorded-scene
./scripts/test_simulator.sh
```

Use separate terminals for the running backend and Simulator/test commands. Full setup and the runtime pairing workaround are recorded in [setup](../docs/setup.md).

## Observed setup failures and fixes

The Xcode license was accepted locally by the user. The iOS runtime was missing, so the agent downloaded and installed the 8.52 GB iOS 26.5 Apple silicon runtime.

The global developer directory still points to Command Line Tools. The scripts use the explicit Xcode developer directory. Simulator was not registered under its short app name, so the launcher now opens its full bundle path.

Xcode preferred runtime build 23F81a, while installed runtime 23F73 was available through `simctl`. Xcode rejected all Simulator destinations. The supported override `simctl runtime match set iphoneos26.5 23F73` made the installed destination eligible. The app then built and launched successfully.

The first UI test reached audio initialization, then Core Audio aborted with `Initialize: RPC timeout. Apparently deadlocked. Aborting now.` The Mac's default virtual input advertised eight channels. The app now requests one input channel after activating the audio session, in the order specified by [Apple's API documentation](https://developer.apple.com/documentation/avfaudio/avaudiosession/setpreferredinputnumberofchannels%28_%3A%29). Startup logs then reported one active channel and `Audio engine started`. A Simulator guard rejects a remaining unsupported multichannel route before creating input I/O. No captured audio is logged.

The second test exposed a session identifier boundary error. Swift interpolated UUIDs as uppercase strings, while the backend stored lowercase map keys. The client now emits lowercase session paths; the backend also accepts either case. A backend regression test covers submission, cancellation, and deletion through uppercase UUID paths.

The first successful screenshot showed the keyboard hiding the transcript. Sending text now dismisses the keyboard and new replies scroll into view. The source badge was moved so the large table label remains visible. The test now requires the reply to be hittable before capturing evidence.

## Measured successful UI flow

The UI test launched the actual native app, started the scene, submitted a text question about the cup color, received a real model answer, verified the reply was visible, and ended the session. Ending cleared frame history and the local transcript.

Two completed checks before the audio-lifecycle extension passed in 21.880 and 20.874 seconds. The latter used six sampled frames; the model call took 3,714 ms, the newest frame age at response was 4,246 ms, and reported cost was $0.00588075. These are backend/request measurements, not first-audible-answer measurements.

Evidence is retained in ignored `runs/SimulatorUITests-94465a14.xcresult` and `runs/SimulatorUITests-b1fffda9.xcresult`. The second bundle contains a screenshot with the visible reply. Raw logs and screenshots remain under ignored `runs/`.

Four native XCTest core tests passed. Backend checks include a regression for uppercase Swift session UUID paths. Documentation link checks and source parsing are separate checks and do not replace the measured build or UI run.

## Limits and next step

The user reports no microphone connected to this Mac. The detected Jump Desktop input is a virtual route. Successful initialization does not prove speech is arriving. The final isolated output test muted microphone analysis and waited for the audio engine’s completion callback. The UI state alone was not used as playback proof. A person has not confirmed audible output. No live spoken question, voice interruption trial, or ten-minute feedback run has been completed.

The client accepts private Tailscale HTTPS hostnames and supports a client-only build configuration. A source archive can be generated without provider credentials or captures. No remote client has been chosen, no private proxy has been enabled, and no cross-machine network request has been tested.

The simulator delivery remains incomplete against its full hands-free acceptance checklist until a real microphone and audible-output test are available. Physical iPhone validation remains a separate later stage.

## Final isolated playback check

The stronger completion check first exposed an additional audio problem: speech generation reconfigured the audio session and left the render engine stopped with queued buffers. The implementation now keeps a fixed 48 kHz output graph, converts and owns copies of synthesized PCM buffers, separates the synthesizer’s session from the app’s capture session, and resumes the render engine when speech generation reconfigures it. It tracks actual scheduled-buffer completion and synthesis completion separately.

The final run passed in 25.913 seconds, with zero test failures. The test muted virtual microphone analysis before the typed question, verified a visible reply, waited for the dedicated playback-completed accessibility value, and ended the session. This deliberately isolates output rendering; it does not measure echo cancellation or voice interruption.

Sanitized native logs for this run recorded:

- 17:23:02.597: audio engine started with one input channel.
- 17:23:13.824: rendering resumed and first speech buffer scheduled.
- 17:23:13.841: synthesis finished with 278 buffers pending and the engine running.
- 17:23:17.113: speech playback completed.

Times are America/Los_Angeles on 2026-11-06. The result bundle is ignored `runs/SimulatorUITests-39a04ae1.xcresult`. Its screenshot was exported under `runs/final-simulator-evidence/`. Successful playback callbacks establish engine progress, not sound heard by a person.

Failed UI runs left sessions open until the backend’s four-session limit was reached. The subsequent creation attempt returned a measured 429 `session_limit`. Restarting the local backend cleared those test sessions without resetting the spending ledger. The UI test now closes any surviving session in teardown, including after assertion failure.

Xcode also logged an optional diagnostics-collection warning because the global developer directory still points to Command Line Tools. The explicit-directory build, test execution, result bundle, and screenshot export succeeded. The final log reports `TEST SUCCEEDED`.

Total accounted OpenRouter spending after the current UI and playback checks: $0.10209795. No unsettled reservations remained at this snapshot. The $10 project allowance and shared-credential limits were not changed.

The later [camera interface revision](2026-11-06-camera-ui.md) makes the fixture explicit and keeps actual demos on live front or rear cameras. The original UI observations above describe the earlier interface.
