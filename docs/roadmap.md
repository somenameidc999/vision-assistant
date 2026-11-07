# Roadmap

Updated: 2026-11-06.

## 0. Direction

- [x] Select personal native iOS app, OpenRouter, and a Mac backend.
- [x] Select Simulator development first and live iPhone cameras for the actual demo.
- [x] Select hands-free interaction, interruption, and recent scene history.
- [x] Set a $10 validation budget.

## 1. Feasibility and snapshot evidence

- [x] Validate OpenRouter authentication without exposing the credential.
- [x] Run image-plus-text requests on both selected models.
- [x] Run combined speech-plus-images requests with structured output.
- [x] Compare the same 20 controlled visual questions on both models.
- [x] Record quality, unsupported claims, model delay, cost, and limitations.

Complete for the limited fixture set. A broad ordinary-scene evaluation remains future work. Cloud Vision comparison is deferred because OpenRouter is the selected integration.

## 2. Backend and app implementation

- [x] Implement authenticated sessions, validation, cancellation, history, and spending accounting.
- [x] Exercise the actual local API with image, follow-up, and audio requests.
- [x] Implement native UI, explicit development video, front/rear camera source, voice capture, speech detection, and reply playback.
- [x] Generate a licensed scene asset and Xcode project.
- [x] Run backend checks and executable Swift core checks.
- [x] Compile the native iOS target with full Xcode.

The native app builds and its scene-question UI test passed against the real backend. Live voice is user-confirmed on iPhone; formal performance and feedback measurements remain pending.

## 3. Simulator delivery

Xcode 26.6 and an iOS 26.5 runtime are installed. The app runs on an iPhone 17 Pro simulator. The user reports no microphone connected to this Mac. The physical iPhone is now available and has user-confirmed live interaction. Simulator microphone verification remains pending.

- [x] Install Xcode 26.6.
- [x] Complete Apple license setup and install an iOS 26 simulator runtime.
- [x] Build and launch the app.
- [ ] Verify live microphone input and audible reply playback.
- [ ] Complete the [simulator acceptance checklist](demo.md).
- [ ] Fix measured failures before calling the simulator demo complete.

## 4. Physical iPhone

- [x] Connect an iPhone and configure free Personal Team signing.
- [x] Support the connected iPhone on iOS 16.6.1 without an OS update.
- [x] Obtain user confirmation of full-screen camera use, spoken interaction, and live words.
- [ ] Verify real camera orientation, permissions, and local-network access.
- [ ] Measure hands-free behavior with the actual speaker and microphone.
- [ ] Run the ten-minute physical-device checklist.

This stage does not block the first simulator delivery. It does block claiming that the real-camera experience works.

## Portability preparation

- [x] Add client-only configuration without an OpenRouter credential.
- [x] Accept private Tailscale HTTPS URLs in the native client.
- [x] Provide a credential-free source archive command.
- [ ] Choose the other Mac.
- [x] Enable a private Tailscale Serve proxy and verify Mac-side HTTPS requests.
- [ ] Verify the private connection from the iPhone or another client.
