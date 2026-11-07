import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { randomUUID } from 'node:crypto';
import { Budget } from './budget.js';
import { OpenRouter, models } from './openrouter.js';
import type { Turn } from './domain.js';
import { acquireRunLock } from './runLock.js';

// Run after bootstrap and make_fixtures. Records remain ignored until a human scores them.
const root = resolve(import.meta.dirname, '../..');
const release = acquireRunLock(resolve(root, 'runs/budget.lock'));
const cases = JSON.parse(readFileSync(resolve(root, 'runs/fixtures/cases.json'), 'utf8')) as Array<{
  id: string; image: string; question: string; expected: string; sha256: string;
}>;
const key = process.env.OPENROUTER_API_KEY;
if (!key) throw new Error('Missing OPENROUTER_API_KEY.');
let seedCost = 0;
for (const model of models) {
  const summary = JSON.parse(readFileSync(resolve(root, `runs/feasibility/${model.replace('/', '_')}-summary.json`), 'utf8'));
  seedCost += summary.results.reduce((sum: number, row: any) => sum + (row.usage?.cost ?? 0), 0);
}
const budget = new Budget(resolve(root, 'runs/budget.json'), 2, seedCost);
const results: any[] = [];
for (const model of models) {
  const gateway = new OpenRouter(key, model); await gateway.checkCatalog();
  for (const sample of cases) {
    const turn: Turn = { turnId: randomUUID(), text: sample.question, frames: [{ id: randomUUID(), sourceId: randomUUID(),
      capturedAt: new Date().toISOString(), jpeg: readFileSync(resolve(root, 'runs/fixtures', sample.image)).toString('base64') }] };
    budget.reserve(turn.turnId);
    const start = performance.now();
    try {
      const reply = await gateway.answer(turn, [], AbortSignal.timeout(30000));
      budget.settle(turn.turnId, reply.usage.costUSD);
      results.push({ caseId: sample.id, expected: sample.expected, sha256: sample.sha256,
        ...reply, elapsedMs: Math.round(performance.now() - start), score: 'unscored', unsupportedClaims: null });
      console.log(JSON.stringify({ caseId: sample.id, model, elapsedMs: results.at(-1).elapsedMs, cost: reply.usage.costUSD }));
    } catch (error: any) {
      results.push({ caseId: sample.id, model, error: error.code ?? 'request_failed', score: 'failed' });
      console.log(JSON.stringify({ caseId: sample.id, model, error: error.code ?? 'request_failed' }));
    }
    writeFileSync(resolve(root, 'runs/baseline.json'), JSON.stringify({ results, accountedUSD: budget.used }, null, 2), { mode: 0o600 });
  }
}
release();
