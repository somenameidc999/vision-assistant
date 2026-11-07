# Project brief

Updated: 2026-11-06.

## Confirmed direction

Build a personal native iOS assistant that answers spoken questions about ordinary camera scenes. The actual demo uses a live front or rear iPhone camera. An explicit Debug Simulator mode uses a labeled prerecorded scene for development. A physical iPhone is not available for testing yet.

The conversation is hands-free after an explicit start. The user can interrupt answers. The assistant uses the current view and up to 30 seconds of sampled scene history. Cloud model requests use OpenRouter. A local Mac backend holds the credential. The validation budget is $10.

## First delivery

The user starts a session, asks about the scene, hears an answer, asks a follow-up or recent-change question, interrupts an answer, and ends the session. A text input supports troubleshooting and microphone denial. The app shows the source mode and evidence age.

The simulator video animates a licensed public photograph. The rear-camera source is implemented separately and requires physical-device validation. Synthetic or recorded input must not be described as a live camera run.

## Boundaries

The assistant describes scenes and answers questions. It does not control the device, act autonomously, keep cross-session memory, or run in the background. No public deployment, App Store distribution, Cloud Vision dependency, or custom model training is included.

Frames are sampled once per second. Sampling may miss events. Only selected frames and recorded questions leave the device when a question is submitted. The app and backend do not persist scene content. Provider retention is a separate policy.

## Success and current evidence

The quality target is at least 18 of 20 correct or appropriately uncertain snapshot answers. Five dedicated unanswerable cases must avoid invented facts. The small initial baseline passed, but covers one photograph and controlled variants.

The simulator build and visible text-question conversation now pass. Actual hands-free success still requires verified live microphone input and audible output, 20 spoken-turn delay measurements, ten interruption trials, and a ten-minute feedback test. The user reports no microphone on this Mac and plans to use another machine over Tailscale. Those live checks remain pending. See the [demo checklist](demo.md) and [roadmap](roadmap.md).
