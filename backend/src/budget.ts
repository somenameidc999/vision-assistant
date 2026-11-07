import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';
import { AppError } from './domain.js';

interface Entry { id: string; reserved: number; actual?: number }
/** Reservations survive crashes and uncertain cancellation charges. No content is stored. */
export class Budget {
  private entries: Entry[];
  constructor(private path: string, public limit: number, seedCost = 0) {
    if (!Number.isFinite(limit) || limit <= 0 || limit > 10) throw new Error('Budget limit must be greater than zero and at most $10.');
    this.entries = existsSync(path) ? JSON.parse(readFileSync(path, 'utf8')).entries : [];
    if (seedCost && !this.entries.some(e => e.id === 'feasibility-probes')) {
      this.entries.push({ id: 'feasibility-probes', reserved: seedCost, actual: seedCost }); this.save();
    }
  }
  get used() { return this.entries.reduce((sum, e) => sum + (e.actual ?? e.reserved), 0); }
  reserve(id: string, amount = 0.25) {
    if (this.entries.some(e => e.id === id)) throw new AppError(409, 'duplicate_turn', 'Use a new turn identifier.');
    if (this.used + amount > this.limit) throw new AppError(402, 'budget_exhausted', 'The demo spending allowance is exhausted.');
    this.entries.push({ id, reserved: amount }); this.save();
  }
  settle(id: string, cost: number | null) {
    const entry = this.entries.find(e => e.id === id);
    if (entry && cost !== null && Number.isFinite(cost) && cost >= 0) { entry.actual = cost; this.save(); }
  }
  private save() {
    mkdirSync(dirname(this.path), { recursive: true });
    writeFileSync(this.path + '.tmp', JSON.stringify({ entries: this.entries }, null, 2), { mode: 0o600 });
    renameSync(this.path + '.tmp', this.path);
  }
}
