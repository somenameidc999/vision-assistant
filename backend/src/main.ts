import { mkdirSync, readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import { buildApp } from './app.js';
import { Budget } from './budget.js';
import { OpenRouter } from './openrouter.js';
import { acquireRunLock } from './runLock.js';

const root = fileURLToPath(new URL('../../', import.meta.url));
const runs = resolve(root, 'runs');
const token = process.env.SESSION_TOKEN, key = process.env.OPENROUTER_API_KEY;
if (!token || token.length < 32 || !key) throw new Error('Run scripts/bootstrap.py to create local configuration.');
const host = process.env.HOST ?? '127.0.0.1';
if (host !== '127.0.0.1') throw new Error('Set HOST=127.0.0.1. Use the private iPhone proxy or Tailscale Serve for other devices.');
mkdirSync(runs, { recursive: true });
acquireRunLock(resolve(runs, 'budget.lock'));
let seedCost = 0;
try { for (const file of readdirSync(resolve(runs, 'feasibility'))) if (file.endsWith('-summary.json')) {
  const probe = JSON.parse(readFileSync(resolve(runs, 'feasibility', file), 'utf8'));
  seedCost += probe.results.reduce((sum: number, result: any) => sum + (result.usage?.cost ?? 0), 0);
} } catch { /* No feasibility runs on a new checkout. */ }
const gateway = new OpenRouter(key, process.env.OPENROUTER_MODEL);
await gateway.checkCatalog();
const budget = new Budget(resolve(runs, 'budget.json'), Number(process.env.BUDGET_LIMIT_USD ?? 10), seedCost);
const app = buildApp({ token, gateway, budget, metricsPath: resolve(runs, 'metrics.jsonl') });
const port = Number(process.env.PORT ?? 18787);
await app.listen({ host, port });
console.log(`Vision Assistant backend ready on ${host}:${port}. Content logging is disabled.`);
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => { void app.close().then(() => process.exit(0)); });
