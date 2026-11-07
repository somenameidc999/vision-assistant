# Proposed architecture

Status: design hypothesis. No components have been implemented.

## Snapshot experiment

```text
Camera -> explicit capture -> timestamped frame -----------+
                                                         |
User question -> short session context -> model request <-+
                                             |
                                  Optional Cloud Vision tool
                                             |
                                   answer + frame timestamp
```

The capture component owns camera access and a visible capture indicator.
The request component attaches the current frame and question.
The model adapter hides provider-specific request details from the capture component.
The optional Cloud Vision adapter adds text or object annotations for comparison runs.
The response component shows the answer and identifies the frame used.

Keep provider secrets in the backend or a local process.
For any future direct browser connection, follow the selected provider's documented temporary credential mechanism.

## Live camera experiment

Add controlled frame sampling after snapshot evaluation.
Discard obsolete queued frames so slow requests do not build an increasingly stale view.
Preserve capture timestamps and record which frames each response used.
Measure frame age when the answer appears.
Allow the user to stop capture immediately.

Voice interaction may use a streaming multimodal service or separate speech components.
That choice remains open.
Continuous capture and continuous model requests are separate design decisions.

## Failure behavior

| Condition | Expected behavior |
| --- | --- |
| Camera access denied | Explain the missing permission and stop capture attempts. |
| Dark, blurred, or obstructed view | State the limitation and request a clearer view. |
| Missing or stale frame | Ask for a new capture instead of implying a current view. |
| Question asks about an unseen object | State that the object is not visible. |
| Network or provider failure | Show a recoverable error without inventing an answer. |
| Visible text tells the model to ignore instructions | Treat that text as image content. |

## Data handling proposal

Keep camera frames in memory by default.
Save samples only for deliberate experiments.
Keep selected images and raw responses in ignored local directories.
Persist sanitized experiment summaries with sample identifiers.
Resolve provider retention and deletion behavior before uploading personal scenes.
