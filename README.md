# Vision Assistant

A personal iOS camera conversation demo. Ask questions aloud about the scene, ask follow-up questions, and interrupt spoken answers.

**Current status:** installed and launched on the user's iPhone 12 running iOS 16.6.1. The user confirmed the live camera, spoken interaction, live words, and full-screen interface. The Simulator UI tests verify layout, a real model answer, isolated playback completion, and session cleanup. Formal voice-delay, interruption, and ten-minute feedback measurements remain pending.

The iPhone demo uses the live rear or front camera. Camera failures show an error; the app never substitutes a video. An explicitly enabled Simulator development mode uses a labeled animated CC0 photograph. No source records to the photo library.

## Run

Follow [setup](docs/setup.md) to install dependencies and Xcode. Local configuration already exists on the development Mac; it is ignored by Git.

```sh
./scripts/run_backend.sh
```

In another terminal, after full Xcode and an iOS 26 runtime are installed:

```sh
./scripts/run_simulator.sh --dev-prerecorded-scene
```

The development flag works only in Debug Simulator builds. Without the flag, Simulator reports that a live camera is unavailable.

For a physical iPhone running iOS 16.6 or later, follow the [iPhone install guide](docs/iphone.md).

Tap the centered camera button to start. Allow camera and microphone access. Ask “What do you see?” Use the text field if the microphone route is unavailable. Use the camera-switch icon to alternate front and rear cameras on iPhone. Mute, stop speaking, and end use icons with accessibility labels. Long-press the start button for Connection settings. Follow the [demo and validation checklist](docs/demo.md).

## Design

- Native SwiftUI app supporting iOS 16.6 or later.
- One sampled frame per second, held locally for 30 seconds.
- Up to six timestamped frames and one spoken question per OpenRouter request.
- Last eight conversation turns retained only during a session.
- Apple speech synthesis for replies; voice processing reduces speaker feedback.
- On-device live words during speech, with no cloud transcription fallback.
- Full-screen camera with conversation and icon controls overlaid.
- Question-time frame refresh, millisecond timestamps, and backend clock alignment.
- Node.js 22 and TypeScript backend on the Mac, bound to localhost by default.
- OpenRouter credential stays on the Mac. Frames, audio, and conversation content are not persisted by the app or backend.
- Metadata-only spending ledger and measurements survive backend restarts under ignored `runs/`.

Cloud providers process selected frames and questions. Training restrictions do not guarantee zero retention. See [OpenRouter findings](docs/research/openrouter.md).

## Evidence and checks

```sh
./scripts/check.sh
```

The checks include TypeScript, backend behavior tests, executable Swift core checks, Swift syntax parsing, relative documentation links, and whitespace checks. The native build and Simulator UI test also passed. Run `./scripts/test_simulator.sh` with the backend running to repeat the UI check.

The [first baseline](experiments/2026-11-06-baseline.md) contains measured model results. The baseline is limited to one public photograph and controlled variants. The [feasibility record](experiments/2026-11-06-feasibility.md) distinguishes synthesized audio from a real microphone.

Read the [project brief](docs/project-brief.md), [architecture](docs/architecture.md), [API contract](docs/api.md), [roadmap](docs/roadmap.md), and [decision log](docs/decisions.md). The [initial Google research](docs/research/google-vision.md) remains historical research; Cloud Vision is not a dependency.

For another Mac, see [client-only setup over Tailscale](docs/setup.md#another-mac-over-tailscale). Generate a portable archive with `python3 scripts/package_demo.py`. The [Simulator experiment](experiments/2026-11-06-simulator.md) records fixes, proof, and remaining limits.

The [iPhone experiment](experiments/2026-11-06-iphone.md) records physical setup, user confirmation, observed failures, budget reservations, and remaining acceptance measurements.
