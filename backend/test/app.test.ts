import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { buildApp } from '../src/app.js';
import { Budget } from '../src/budget.js';
import type { Exchange, ModelGateway, ModelReply, Turn } from '../src/domain.js';
import { acquireRunLock } from '../src/runLock.js';
const token = 'test-token-that-is-not-a-real-secret';
const headers = { authorization: `Bearer ${token}` };
function turn(): Turn {
  // Minimal SOF header exercises dimensions without depending on external media.
  return { turnId: randomUUID(), text: 'What is visible?', frames: [{ id: randomUUID(), sourceId: randomUUID(),
    capturedAt: new Date().toISOString(), jpeg: Buffer.from([255,216,255,192,0,17,8,1,224,2,128,3,0,0,0,0,255,217]).toString('base64') }] };
}
const answer: ModelReply = { transcript: 'What is visible?', answer: 'A cup.', model: 'mock', usage: { inputTokens: 1, outputTokens: 1, costUSD: .01 } };
function setup(t: any, gateway: ModelGateway = { answer: async () => answer }, limit = 10) {
  const dir = mkdtempSync(join(tmpdir(), 'vision-test-'));
  const path = join(dir, 'budget.json'), metricsPath = join(dir, 'metrics.jsonl');
  const budget = new Budget(path, limit);
  const app = buildApp({ token, gateway, budget, metricsPath });
  t.after(async () => { await app.close(); rmSync(dir, { recursive: true, force: true }); });
  return { app, budget, path, metricsPath };
}
test('authorization, successful turn, metadata-only metrics, eight-turn context and replay protection', async t => {
  const historySizes: number[] = [];
  const { app, budget, metricsPath } = setup(t, { answer: async (_turn, history) => { historySizes.push(history.length); return answer; } });
  assert.equal((await app.inject({ method: 'POST', url: '/v1/sessions' })).statusCode, 401);
  const id = (await app.inject({ method: 'POST', url: '/v1/sessions', headers })).json().sessionId;
  let first!: Turn;
  for (let i = 0; i < 10; i++) {
    const payload = turn(); if (i === 0) first = payload;
    const response = await app.inject({ method: 'POST', url: `/v1/sessions/${id}/turns`, headers, payload });
    assert.equal(response.statusCode, 200, response.body);
    assert.equal(response.json().frames[0].jpeg, undefined);
  }
  assert.deepEqual(historySizes, [0,1,2,3,4,5,6,7,8,8]);
  first.frames[0]!.capturedAt = new Date().toISOString();
  assert.equal((await app.inject({ method: 'POST', url: `/v1/sessions/${id}/turns`, headers, payload: first })).statusCode, 409);
  assert.ok(Math.abs(budget.used - .1) < 1e-9);
  const metrics = readFileSync(metricsPath, 'utf8');
  assert.ok(!metrics.includes('A cup') && !metrics.includes('What is visible') && !metrics.includes(first.frames[0]!.jpeg));
});
test('reject stale frames, mixed scenes, malformed images/audio and ambiguous input before spending', async t => {
  const { app, budget } = setup(t);
  const id = (await app.inject({ method: 'POST', url: '/v1/sessions', headers })).json().sessionId;
  const stale = turn(); stale.frames[0]!.capturedAt = new Date(Date.now() - 5000).toISOString();
  const mixed = turn(); mixed.frames.push({ ...turn().frames[0]! });
  const badImage = turn(); badImage.frames[0]!.jpeg = Buffer.from('not jpeg').toString('base64');
  const audio = turn(); delete audio.text; audio.audio = { format: 'wav', data: Buffer.from('not wav').toString('base64') };
  const both = turn(); both.audio = audio.audio;
  for (const payload of [stale, mixed, badImage, audio, both]) {
    const response = await app.inject({ method: 'POST', url: `/v1/sessions/${id}/turns`, headers, payload });
    assert.ok([400,422].includes(response.statusCode), response.body);
  }
  assert.equal(budget.used, 0);
});
test('cancellation discards a late model answer, settles cost and cannot clear a newer request', async t => {
  const pending: Array<{ resolve: (r: ModelReply) => void; signal: AbortSignal; history: Exchange[] }> = [];
  const { app, budget } = setup(t, { answer: async (_turn, history, signal) => new Promise(resolve => { pending.push({ resolve, signal, history }); }) });
  const id = (await app.inject({ method: 'POST', url: '/v1/sessions', headers })).json().sessionId;
  const first = turn();
  const firstRequest = app.inject({ method: 'POST', url: `/v1/sessions/${id}/turns`, headers, payload: first });
  // inject is a thenable; attach a continuation to actually dispatch it.
  const dispatchedFirst = firstRequest.then(r => r);
  while (pending.length < 1) await new Promise(resolve => setImmediate(resolve));
  assert.equal((await app.inject({ method: 'POST', url: `/v1/sessions/${id}/turns`, headers, payload: turn() })).statusCode, 409);
  await app.inject({ method: 'POST', url: `/v1/sessions/${id}/cancel`, headers, payload: { turnId: first.turnId } });
  assert.equal(pending[0]!.signal.aborted, true);
  const second = turn();
  const dispatchedSecond = app.inject({ method: 'POST', url: `/v1/sessions/${id}/turns`, headers, payload: second }).then(r => r);
  while (pending.length < 2) await new Promise(resolve => setImmediate(resolve));
  pending[0]!.resolve(answer);
  assert.equal((await dispatchedFirst).statusCode, 409);
  pending[1]!.resolve(answer);
  assert.equal((await dispatchedSecond).statusCode, 200);
  assert.equal(pending[1]!.history.length, 0);
  assert.equal(budget.used, .02);
});
test('delete aborts requests and prevents results from restarting a stopped session', async t => {
  let resolve!: (reply: ModelReply) => void;
  let signal!: AbortSignal;
  const { app } = setup(t, { answer: async (_turn, _history, s) => { signal = s; return new Promise(r => { resolve = r; }); } });
  const id = (await app.inject({ method: 'POST', url: '/v1/sessions', headers })).json().sessionId;
  const response = app.inject({ method: 'POST', url: `/v1/sessions/${id}/turns`, headers, payload: turn() }).then(r => r);
  while (!resolve) await new Promise(r => setImmediate(r));
  assert.equal((await app.inject({ method: 'DELETE', url: `/v1/sessions/${id}`, headers })).statusCode, 204);
  assert.equal(signal.aborted, true); resolve(answer);
  assert.equal((await response).statusCode, 409);
});
test('a cancellation arriving before the question prevents provider execution and spending', async t => {
  let calls = 0;
  const { app, budget } = setup(t, { answer: async () => { calls++; return answer; } });
  const id = (await app.inject({ method: 'POST', url: '/v1/sessions', headers })).json().sessionId;
  const payload = turn();
  await app.inject({ method: 'POST', url: `/v1/sessions/${id}/cancel`, headers, payload: { turnId: payload.turnId } });
  const reply = await app.inject({ method: 'POST', url: `/v1/sessions/${id}/turns`, headers, payload });
  assert.equal(reply.statusCode, 409); assert.equal(calls, 0); assert.equal(budget.used, 0);
});
test('session UUIDs accept Swift UUID uppercase path serialization', async t => {
  const { app } = setup(t);
  const id = (await app.inject({ method: 'POST', url: '/v1/sessions', headers })).json().sessionId.toUpperCase();
  const payload = turn();
  assert.equal((await app.inject({ method: 'POST', url: `/v1/sessions/${id}/turns`, headers, payload })).statusCode, 200);
  assert.equal((await app.inject({ method: 'POST', url: `/v1/sessions/${id}/cancel`, headers, payload: { turnId: payload.turnId } })).statusCode, 200);
  assert.equal((await app.inject({ method: 'DELETE', url: `/v1/sessions/${id}`, headers })).statusCode, 204);
});
test('budget survives restart, preserves uncertain charges and refuses an unaffordable reservation', async t => {
  const { budget, path } = setup(t, undefined, .5);
  budget.reserve('one'); budget.reserve('two'); budget.settle('one', .02);
  const restarted = new Budget(path, .5);
  assert.equal(restarted.used, .27);
  assert.throws(() => restarted.reserve('three'), /spending allowance/);
  assert.throws(() => restarted.reserve('two'), /new turn identifier/);
  restarted.settle('two', null);
  assert.equal(restarted.used, .27);
});
test('only one runtime can own the shared experiment and backend ledger', t => {
  const { path } = setup(t);
  const release = acquireRunLock(path + '.lock');
  assert.throws(() => acquireRunLock(path + '.lock'), /already locked/);
  release();
  const releaseAgain = acquireRunLock(path + '.lock');
  releaseAgain();
});

test('a stale turn can be refreshed with the same id without spending twice', async t => {
  let calls = 0;
  const { app, budget } = setup(t, { answer: async () => { calls++; return answer; } });
  const session = (await app.inject({ method: 'POST', url: '/v1/sessions', headers })).json();
  assert.ok(Number.isFinite(Date.parse(session.serverTime)));
  const payload = turn();
  payload.frames[0]!.capturedAt = new Date(Date.now() - 5000).toISOString();
  assert.equal((await app.inject({ method: 'POST', url: `/v1/sessions/${session.sessionId}/turns`, headers, payload })).json().error.code, 'stale_frame');
  assert.equal(calls, 0); assert.equal(budget.used, 0);
  payload.frames[0]!.capturedAt = new Date().toISOString();
  assert.equal((await app.inject({ method: 'POST', url: `/v1/sessions/${session.sessionId}/turns`, headers, payload })).statusCode, 200);
  assert.equal(calls, 1); assert.equal(budget.used, .01);
});
