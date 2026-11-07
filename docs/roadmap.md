# Roadmap

## 0. Establish the research repo

Complete when the goal, sources, open questions, and experiment method are recorded.

- [x] Record the camera-based direction.
- [x] Review initial Google documentation.
- [x] Define candidate approaches and evaluation fields.
- [ ] Select the first device and interaction mode.

## 1. Compare camera snapshots

1. Select 10–20 non-sensitive scenes with known answers.
2. Define a scoring rubric before running models.
3. Implement the direct image-and-question baseline.
4. Run the same questions with Cloud Vision assistance where relevant.
5. Record quality, unsupported claims, latency, and cost.
6. Select an approach using the recorded evidence.

Complete when another developer can reproduce the comparison and inspect failures.
No quality or latency targets are selected yet.

## 2. Build a camera conversation prototype

1. Add explicit camera start and stop controls.
2. Connect question submission to a fresh frame.
3. Add short session context for follow-up questions.
4. Show frame timestamps with answers.
5. Verify camera denial, stale frames, and provider failures.

Complete when a user can ask about a live scene and follow up without uploading files manually.

## 3. Explore live interaction

1. Compare sampled camera requests with a streaming vision service.
2. Add voice if the selected interaction requires voice.
3. Measure response delay and frame age during moving scenes.
4. Test session recovery and stop behavior.
5. Estimate sustained session cost.

Complete when measured behavior meets targets agreed for the chosen device and use case.

## 4. Choose a product scope

Use experiment evidence to decide hardware, deployment, privacy, memory, and proactive behavior.
Add product milestones after that decision.
