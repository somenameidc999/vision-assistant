import Fastify from 'fastify';
import { randomUUID, timingSafeEqual } from 'node:crypto';
import { appendFileSync } from 'node:fs';
import { z } from 'zod';
import { AppError, turnSchema, validateScene, type Exchange, type ModelGateway } from './domain.js';
import type { Budget } from './budget.js';

interface Session { history: Exchange[]; seen: Set<string>; touched: number; active?: { turnId: string; controller: AbortController } }
interface Options { token: string; gateway: ModelGateway; budget: Budget; metricsPath?: string }
export function buildApp(options: Options) {
  const app = Fastify({ logger: false, bodyLimit: 6_000_000, requestTimeout: 35_000 });
  const sessions = new Map<string, Session>();
  app.setErrorHandler((error: any, _request, reply) => {
    const known = error instanceof AppError;
    const invalid = error instanceof z.ZodError || error.statusCode === 400 || error.statusCode === 413;
    reply.code(known ? error.status : error.statusCode === 413 ? 413 : invalid ? 400 : 500).send({ error: {
      code: known ? error.code : invalid ? 'invalid_request' : 'internal_error',
      message: known ? error.message : invalid ? 'The request is invalid or too large.' : 'The backend could not complete the request.' } });
  });
  app.addHook('onRequest', async (request) => {
    if (request.url === '/health') return;
    const received = Buffer.from(request.headers.authorization ?? '');
    const expected = Buffer.from(`Bearer ${options.token}`);
    if (received.length !== expected.length || !timingSafeEqual(received, expected))
      throw new AppError(401, 'unauthorized', 'Check the backend session token.');
  });
  function getSession(id: string) {
    const session = sessions.get(id.toLowerCase());
    if (!session) throw new AppError(404, 'session_expired', 'Start a new session.');
    session.touched = Date.now(); return session;
  }
  const cleanup = setInterval(() => {
    for (const [id, session] of sessions) if (Date.now() - session.touched > 15 * 60_000) {
      session.active?.controller.abort(); sessions.delete(id);
    }
  }, 60_000).unref();
  app.addHook('onClose', async () => { clearInterval(cleanup); for (const session of sessions.values()) session.active?.controller.abort(); sessions.clear(); });
  app.get('/health', async () => ({ status: 'ok', protocolVersion: 1 }));
  app.post('/v1/sessions', async (_request, reply) => {
    if (sessions.size >= 4) throw new AppError(429, 'session_limit', 'End another session before starting one.');
    const sessionId = randomUUID();
    sessions.set(sessionId, { history: [], seen: new Set(), touched: Date.now() });
    return reply.code(201).send({ sessionId, serverTime: new Date().toISOString(), budget: { limitUSD: options.budget.limit, accountedUSD: options.budget.used } });
  });
  app.delete<{ Params: { id: string } }>('/v1/sessions/:id', async (request, reply) => {
    const id = request.params.id.toLowerCase();
    const session = sessions.get(id);
    session?.active?.controller.abort(); sessions.delete(id);
    return reply.code(204).send();
  });
  app.post<{ Params: { id: string } }>('/v1/sessions/:id/cancel', async (request) => {
    const { turnId } = z.object({ turnId: z.string().uuid() }).parse(request.body);
    const session = getSession(request.params.id);
    // A cancellation can arrive before its question request. Tombstone the UUID.
    session.seen.add(turnId);
    if (session.active?.turnId === turnId) { session.active.controller.abort(); session.active = undefined; }
    const exchange = session.history.find(h => h.turnId === turnId);
    if (exchange) exchange.interrupted = true;
    return { cancelled: true };
  });
  app.post<{ Params: { id: string } }>('/v1/sessions/:id/turns', async (request, reply) => {
    const session = getSession(request.params.id), turn = turnSchema.parse(request.body);
    validateScene(turn);
    if (session.active) throw new AppError(409, 'turn_in_progress', 'Cancel the current question before asking another.');
    if (session.seen.has(turn.turnId)) throw new AppError(409, 'duplicate_turn', 'Use a new turn identifier.');
    options.budget.reserve(turn.turnId);
    session.seen.add(turn.turnId);
    const active = { turnId: turn.turnId, controller: new AbortController() };
    session.active = active;
    const started = performance.now();
    const disconnected = () => { if (!reply.raw.writableEnded) active.controller.abort(); };
    reply.raw.on('close', disconnected);
    try {
      const answer = await options.gateway.answer(turn, session.history.slice(), active.controller.signal);
      options.budget.settle(turn.turnId, answer.usage.costUSD);
      if (active.controller.signal.aborted || session.active !== active || !sessions.has(request.params.id.toLowerCase()))
        throw new AppError(409, 'cancelled', 'The question was cancelled.');
      session.history.push({ turnId: turn.turnId, transcript: answer.transcript, answer: answer.answer, interrupted: false });
      session.history = session.history.slice(-8);
      const timing = { providerMs: Math.round(performance.now() - started),
        newestFrameAgeAtResponseMs: Date.now() - Math.max(...turn.frames.map(f => Date.parse(f.capturedAt))) };
      if (options.metricsPath) appendFileSync(options.metricsPath, JSON.stringify({ at: new Date().toISOString(),
        turnId: turn.turnId, model: answer.model, inputType: turn.audio ? 'audio' : 'text', frameCount: turn.frames.length, timing, usage: answer.usage }) + '\n', { mode: 0o600 });
      return { turnId: turn.turnId, ...answer, frames: turn.frames.map(({ jpeg: _jpeg, ...frame }) => frame), timing,
        budget: { limitUSD: options.budget.limit, accountedUSD: options.budget.used } };
    } finally {
      reply.raw.off('close', disconnected);
      if (session.active === active) session.active = undefined;
    }
  });
  return app;
}
