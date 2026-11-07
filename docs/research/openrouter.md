# OpenRouter implementation findings

Checked: 2026-11-06. The feasibility and baseline records contain actual requests. This page separates documentation from observed behavior.

## Documented capabilities

The [Responses API](https://openrouter.ai/docs/api_reference/responses/overview) accepts compatible multimodal models. [Image input](https://openrouter.ai/docs/guides/overview/multimodal/image-understanding) accepts base64 JPEG data. [Audio input](https://openrouter.ai/docs/guides/overview/multimodal/audio) accepts base64 WAV input. [Structured outputs](https://openrouter.ai/docs/guides/features/structured-outputs) use `text.format` with `json_schema` on this API.

The public [model catalog](https://openrouter.ai/api/v1/models) listed both selected models with image and audio inputs:

| Model identifier | Catalog input price / million tokens | Catalog output price / million tokens |
| --- | --- | --- |
| `google/gemini-3.8-flash` | $0.825 | $4.125 |
| `google/gemini-3.5-flash-lite` | $0.30 | $2.50 |

The listed image/audio rates match input rates for these models at the time checked. Actual routed pricing can differ. Report actual `usage.cost` separately from catalog estimates. Recheck model availability, endpoint support, limits, and pricing before new experiments. The backend checks required modalities and conservative price ceilings at startup.

## Data handling

[Provider logging documentation](https://openrouter.ai/docs/guides/privacy/provider-logging) distinguishes training policy from retention. Requests set `provider.data_collection` to `deny` and require supported request parameters. This excludes training-permitted routes; it does not guarantee no retention.

The [provider directory](https://openrouter.ai/providers/) listed Google Vertex with no training and zero routine retention, and Google AI Studio with no training and 55-day retention. The initial successful combined request’s generation metadata reported provider `Google` and resolved model `google/gemini-3.8-flash-20260902`. Later requests may route differently. Safety, abuse-monitoring, and legal exceptions still apply. [OpenRouter data collection](https://openrouter.ai/docs/guides/privacy/data-collection)

The implementation does not enable OpenRouter prompt logging. Existing account-level opt-ins were not changed or verified. The initial demo uses public licensed images and synthesized audio. Before uploading personal scenes, review account settings and the current selected endpoint’s policy. Do not claim provider zero retention based on the app’s in-memory storage.

## Observed behavior

Both models accepted a combined request with two images, WAV audio, and a JSON schema. Both transcribed the synthesized question and answered the image comparison. The default model’s combined request took 4,176 ms and reported $0.00248775.

Neither a Responses API request nor streamed text proves continuous video or full-duplex audio support. The demo uses local audio turn detection, sampled images, one model request per question, and local speech synthesis. The model is not continuously watching the scene.
