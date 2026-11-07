# Experiment: combined images and speech

Date: 2026-11-06
Status: API feasibility passed. Simulator and live audio validation remain pending.
Base commit: `40ae6ea`; implementation changes were uncommitted during this run.

## Question and method

Can OpenRouter accept timestamped images, WAV speech, and a strict JSON response schema in one request?

The versioned probe generates two 640 × 480 JPEG drawings of a blue cylinder/cup at different horizontal positions. macOS Samantha synthesizes “What color is the cup, and how did its position change?” at 16 kHz PCM16. No live microphone or personal camera data is used.

```sh
.venv/bin/python scripts/probe_openrouter.py
.venv/bin/python scripts/probe_openrouter.py --model google/gemini-3.5-flash-lite
```

The exact source hashes and raw responses remain in ignored `runs/feasibility/`. The input fixture generator and request schema are in the probe source. The request sets `provider.data_collection=deny`, `require_parameters=true`, `store=false`, and an output limit of 512 tokens.

## Observed results

| Model | Mode | HTTP | Request ms | Reported cost |
| --- | --- | --- | --- | --- |
| `google/gemini-3.5-flash-lite` | image_text | 200 | 1580 | $0.00042260 |
| `google/gemini-3.5-flash-lite` | images_audio | 200 | 1811 | $0.00080260 |
| `google/gemini-3.8-flash` | image_text | 200 | 3774 | $0.00117900 |
| `google/gemini-3.8-flash` | images_audio | 200 | 4176 | $0.00248775 |

The default model correctly identified blue and a shift from left to right. The cheaper model denied that the single synthetic shape was a cup in the text test, but called it a blue cylinder in the combined test and described its shift correctly. Both combined tests transcribed the synthesized question and returned valid structured output.

The generation metadata for the default combined call reported provider `Google` and resolved model `google/gemini-3.8-flash-20260902`. The successful format is evidence for this integration, not a promise about every routed endpoint.

## Local API smoke test

The actual HTTP backend completed session creation, an image question, a contextual follow-up, a combined two-image/WAV question, and session deletion. The three successful round trips took 3237 ms, 5793 ms, 8494 ms. The audio answer correctly distinguished the animated photograph shifting from a physical object moving.

The 8,494 ms speech-request round trip does not establish the five-second first-audible-answer target. No actual microphone, speaker output, interruption, or ten-minute feedback test ran.

A prior smoke attempt also made two successful text requests before rejecting a noncanonical WAV header. Those charges remain in the shared ledger. The smoke fixture now normalizes that WAV header to the app's canonical format. Another smoke attempt was rejected before model execution because its empty session POST incorrectly declared JSON; the test client was corrected.

Total accounted OpenRouter spending after feasibility, baseline, and smoke requests: $0.05819295. This figure includes the two earlier successful text requests. Raw results and accounting remain under ignored `runs/`.

## Limits and next check

The combined API gate passed, so implementation continued. Xcode was initially missing and its downloader requested local Apple sign-in. Xcode 26.6 files were subsequently installed by the user, but Apple license and simulator setup remain pending. An actual iOS build attempt stopped at the license check. The iOS project has been generated and Swift source syntax checked. The shared frame-history and voice-detector code passed executable command-line checks. These checks do not establish a successful iOS build.

Complete the [simulator acceptance checklist](../docs/demo.md) after Xcode installation. Primary capability, pricing, and data-policy sources are recorded in the [OpenRouter note](../docs/research/openrouter.md), checked 2026-11-06.
