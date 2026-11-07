# Initial Google vision research

Checked: 2026-11-05. No provider requests or camera experiments have run.

## Documented facts

Google's [Vision AI overview](https://cloud.google.com/vision) distinguishes specialized vision services from multimodal generative models.
The product family includes Cloud Vision API, Document AI, and Video Intelligence.

[Cloud Vision API](https://docs.cloud.google.com/vision/docs/features-list) provides image labels, object locations, and optical character recognition (OCR), which converts visible text into machine-readable text.
Object results include confidence scores and bounding polygons.
Face detection does not identify specific people.
These features produce image annotations; they do not supply the full conversational assistant.

[Gemini image understanding](https://ai.google.dev/gemini-api/docs/image-understanding) supports image captioning and visual question answering.
Images can be passed alongside text.
This makes a direct image-and-question experiment possible.

[Gemini Live](https://ai.google.dev/gemini-api/docs/live) supports streaming audio, images, and text for real-time voice and vision interaction.
The overview currently specifies a stateful WebSocket connection and JPEG image input at up to one frame per second.
Recheck those limits for the chosen model before building.

[Cloud Vision pricing](https://cloud.google.com/vision/pricing) counts each feature applied to an image as a billable unit.
Applying two features can incur two units for one frame.
The published monthly free tier covers the first 1,000 units for each feature.
Storage, compute, and multimodal model usage require separate estimates.

## Inferences

A camera assistant needs capture, frame timing, conversational context, and response behavior in addition to image analysis.
A direct multimodal path is a useful baseline because the user asks open-ended questions.
An OCR tool may improve text-heavy cases, but that improvement is unmeasured.
Sampled frames can miss short events between captures.

## Proposed comparison

| Candidate | Experiment | Main uncertainty |
| --- | --- | --- |
| Gemini image understanding | Send a camera snapshot and question. | Grounding, small text, and response delay. |
| Cloud Vision plus a conversational model | Add extracted text or object annotations to the same question. | Whether extra quality justifies extra delay and cost. |
| Gemini Live | Run camera and voice follow-ups in one session. | Streaming behavior, freshness, interruptions, and sustained cost. |

These are candidates, not selected production dependencies.
The Gemini API and Google Cloud services have distinct setup and billing paths.
Do not assume credentials or service policies are interchangeable.

## Next research

1. Verify setup and data handling for the exact service selected for an experiment.
2. Estimate cost using the chosen model, frame rate, session duration, and feature count.
3. Run the snapshot baseline on the same local scene set used by the assisted pipeline.
4. Evaluate a local model if cloud processing conflicts with device or privacy requirements.

Current prices, regional availability, quotas, and model identifiers must be checked again when an executable experiment is added.
