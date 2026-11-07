# Vision Assistant

A research repo for building an AI assistant that can see through a camera and answer questions about the scene.

## Project direction

The user describes the input as “whatever is on the camera it has.”
The camera is the primary input. The device and camera hardware remain open.
The assistant should explain visible evidence, answer follow-up questions, and state when the view is unclear.

Status: research and experiment design. No assistant application exists yet.

## Start here

1. Read the [project brief](docs/project-brief.md).
2. Review the [initial Google research](docs/research/google-vision.md).
3. Follow the [roadmap](docs/roadmap.md).
4. Record experiment results with the [experiment template](experiments/TEMPLATE.md).

## Initial approach

Compare a multimodal model, which accepts images and language together, with a pipeline that also uses Google Cloud Vision for specialized image analysis.
Evaluate camera snapshots first. Explore live camera and voice interaction next.
Keep the model provider and application stack open until experiments support a choice.

The initial research source is [Google Cloud Vision](https://cloud.google.com/vision).
The [research note](docs/research/google-vision.md) separates documented capabilities from proposed design choices.

## Repository layout

```text
docs/project-brief.md          Goals, boundaries, and open questions
docs/research/google-vision.md Source-backed findings and hypotheses
docs/architecture.md          Proposed camera-to-answer flow
docs/roadmap.md               Milestones and completion criteria
docs/decisions.md              Decision history
experiments/TEMPLATE.md        Repeatable experiment record
data/README.md                 Local sample handling
AGENTS.md                      Instructions for future repo work
```

No credentials, paid services, camera access, or dependencies are needed to read this repo.
Setup commands will be added with the first executable experiment.
