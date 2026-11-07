# Project brief

Created: 2026-11-05

## Confirmed direction

Build an AI assistant with vision.
Research comes before the full application.
The assistant sees whatever is in its camera view.
Google Cloud Vision is the first research lead, not a confirmed provider choice.

## Candidate interactions

These examples are proposed experiments, not confirmed requirements.

| User question | Useful assistant behavior |
| --- | --- |
| “What do you see?” | Describe the main visible objects and scene. |
| “What does that sign say?” | Read visible text and identify unreadable parts. |
| “Where is the blue cup?” | Describe the location relative to visible objects. |
| “What changed?” | Compare timestamped views and state the observation gap. |
| “Can you see the label now?” | Use the latest frame and ask for a closer view if needed. |

## Proposed first prototype

A user explicitly starts a camera session.
The prototype captures one frame when the user asks a text question.
The model receives the question and frame together.
The prototype displays an answer with the frame timestamp.
The prototype allows a follow-up with a fresh frame.

Start with snapshots to measure basic visual understanding.
The target remains a live camera assistant.
Snapshot quality alone will not prove that live interaction works.

## Proposed boundaries

The first prototype describes scenes and answers questions.
Device control, autonomous actions, persistent memory, and custom model training remain later decisions.
The prototype should not promise that every object or event is visible or recognizable.
The assistant must distinguish observation from guesses.

## Open questions

| Question | Current status |
| --- | --- |
| First device: laptop, phone, embedded device, or wearable? | Open |
| First camera: built-in webcam, phone camera, or external camera? | Open |
| Is voice required in the first usable version? | Open |
| Does the assistant respond only to questions or also notice changes proactively? | Open |
| Is cloud processing acceptable, or must inference run locally? | Open |
| What latency, budget, and session duration are acceptable? | Open |
| Should any scene history survive the current session? | Open |

## Evidence needed

Use varied scenes, lighting, text sizes, motion, occlusion, and camera angles.
Include questions whose answers are not visible.
Measure answer quality, unsupported claims, delay, and cost.
Keep raw camera data local unless a sample is explicitly selected for a cloud experiment.
