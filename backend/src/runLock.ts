import { closeSync, openSync, readFileSync, unlinkSync, writeFileSync } from 'node:fs';

/** One process owns the spending ledger. Never overwrite another process's in-memory balance. */
export function acquireRunLock(path: string) {
  let fd: number;
  try { fd = openSync(path, 'wx', 0o600); }
  catch { throw new Error(`Budget ledger is already locked at ${path}. Stop the other backend or experiment. After a crash, verify its recorded PID has exited before removing the lock.`); }
  const owner = String(process.pid);
  writeFileSync(fd, owner); closeSync(fd);
  const release = () => {
    try { if (readFileSync(path, 'utf8') === owner) unlinkSync(path); } catch { /* Already released. */ }
  };
  process.once('exit', release);
  return release;
}
