import test from 'node:test';
import assert from 'node:assert/strict';
import { OpenRouter } from '../src/openrouter.js';
import type { Turn } from '../src/domain.js';
import { randomUUID } from 'node:crypto';

test('provider adapter sends audio with timed frames and privacy constraints, parses usage', async () => {
  const original = globalThis.fetch;
  const turn: Turn = { turnId: randomUUID(), frames: [{ id: randomUUID(), sourceId: randomUUID(),
    capturedAt: '2026-11-06T12:00:00.000Z', playbackSeconds: 12, jpeg: 'YWJj' }], audio: { data: 'YXVkaW8=', format: 'wav' } };
  let sent: any;
  globalThis.fetch = async (_url, init) => {
    sent = JSON.parse(String(init?.body));
    return new Response(JSON.stringify({ status: 'completed', id: 'provider-id',
      output: [{ content: [{ type: 'output_text', text: JSON.stringify({ transcript: 'What changed?', answer: 'The label changed.' }) }] }],
      usage: { input_tokens: 100, output_tokens: 30, cost: .003 } }), { status: 200 });
  };
  try {
    const gateway = new OpenRouter('not-a-real-key');
    const result = await gateway.answer(turn, [{ turnId: 'previous', transcript: 'Old question', answer: 'Partial answer', interrupted: true }], new AbortController().signal);
    assert.equal(result.usage.costUSD, .003);
    assert.equal(sent.store, false);
    assert.equal(sent.provider.data_collection, 'deny');
    assert.equal(sent.max_output_tokens, 512);
    assert.equal(sent.text.format.type, 'json_schema');
    assert.match(sent.input[2].content, /Interrupted/);
    assert.equal(sent.input[3].content.at(-1).type, 'input_audio');
    assert.ok(sent.input[3].content.some((c: any) => c.type === 'input_text' && c.text.includes('2026-11-06')));
  } finally { globalThis.fetch = original; }
});
test('provider adapter rejects truncated, malformed and failed responses', async () => {
  const original = globalThis.fetch;
  const gateway = new OpenRouter('not-a-real-key');
  const turn: Turn = { turnId: randomUUID(), text: 'Question', frames: [] };
  try {
    for (const body of [ { status: 'incomplete', output: [] }, { status: 'completed', output: [{ content: [{ type: 'output_text', text: '{}' }] }] } ]) {
      globalThis.fetch = async () => new Response(JSON.stringify(body));
      await assert.rejects(gateway.answer(turn, [], new AbortController().signal), /model returned an incomplete answer/);
    }
    globalThis.fetch = async () => new Response('not json');
    await assert.rejects(gateway.answer(turn, [], new AbortController().signal), /unreadable response/);
    globalThis.fetch = async () => new Response('{}', { status: 429 });
    await assert.rejects(gateway.answer(turn, [], new AbortController().signal), /rate limited/);
  } finally { globalThis.fetch = original; }
});
