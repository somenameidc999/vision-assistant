import { z } from 'zod';

export class AppError extends Error {
  constructor(public status: number, public code: string, message: string) { super(message); }
}
const base64 = z.string().max(1_200_000).regex(/^[A-Za-z0-9+/]+={0,2}$/);
export const frameSchema = z.object({
  id: z.string().uuid(), capturedAt: z.string().datetime(),
  sourceId: z.string().uuid(), playbackSeconds: z.number().nonnegative().optional(),
  jpeg: base64,
}).strict();
export const turnSchema = z.object({
  turnId: z.string().uuid(),
  text: z.string().trim().min(1).max(2000).optional(),
  audio: z.object({ format: z.literal('wav'), data: base64 }).strict().optional(),
  frames: z.array(frameSchema).min(1).max(6),
}).strict().refine(t => Boolean(t.text) !== Boolean(t.audio), 'Supply either text or WAV audio.');
export type Turn = z.infer<typeof turnSchema>;
export interface Exchange { turnId: string; transcript: string; answer: string; interrupted: boolean }
export interface Usage { inputTokens: number; outputTokens: number; costUSD: number | null }
export interface ModelReply { transcript: string; answer: string; usage: Usage; model: string; providerResponseId?: string }
export interface ModelGateway {
  answer(turn: Turn, history: Exchange[], signal: AbortSignal): Promise<ModelReply>;
}
export function validateScene(turn: Turn, now = Date.now()) {
  const times = turn.frames.map(f => Date.parse(f.capturedAt));
  if (times.some(t => t > now + 1000 || t < now - 32_000))
    throw new AppError(422, 'invalid_frame_time', 'Frames must come from the current 30-second scene history.');
  if (now - Math.max(...times) > 2000)
    throw new AppError(422, 'stale_frame', 'The current view is stale. Resume the scene and try again.');
  if (new Set(turn.frames.map(f => f.sourceId)).size !== 1 || new Set(turn.frames.map(f => f.id)).size !== turn.frames.length)
    throw new AppError(422, 'mixed_scene', 'Start a new scene history after seeking or changing sources.');
  for (const frame of turn.frames) {
    const data = Buffer.from(frame.jpeg, 'base64');
    // Inspect JPEG dimensions before sending. SOF dimensions bound image token usage.
    if (data[0] !== 0xff || data[1] !== 0xd8 || data.length > 300_000)
      throw new AppError(422, 'invalid_image', 'Supply JPEG frames smaller than 300 KB.');
    let offset = 2, dimensions: [number, number] | undefined;
    while (offset + 8 < data.length) {
      if (data[offset] !== 0xff) break;
      const marker = data[offset + 1]!;
      if (marker === 0xda || marker === 0xd9) break;
      const length = data.readUInt16BE(offset + 2);
      if (length < 2) break;
      if ([0xc0, 0xc1, 0xc2].includes(marker)) {
        dimensions = [data.readUInt16BE(offset + 5), data.readUInt16BE(offset + 7)]; break;
      }
      offset += length + 2;
    }
    if (!dimensions || dimensions.some(v => v < 1 || v > 1024))
      throw new AppError(422, 'invalid_image', 'JPEG frame dimensions must be at most 1024 pixels.');
  }
  if (turn.audio) {
    const wav = Buffer.from(turn.audio.data, 'base64');
    if (wav.length < 44 || wav.toString('ascii', 0, 4) !== 'RIFF' || wav.toString('ascii', 8, 12) !== 'WAVE'
        || wav.toString('ascii', 12, 16) !== 'fmt ' || wav.readUInt32LE(16) !== 16
        || wav.readUInt16LE(20) !== 1 || wav.readUInt16LE(22) !== 1
        || wav.readUInt32LE(24) !== 16000 || wav.readUInt16LE(34) !== 16
        || wav.toString('ascii', 36, 40) !== 'data' || wav.readUInt32LE(40) !== wav.length - 44
        || wav.length > 640_044)
      throw new AppError(422, 'invalid_audio', 'Supply at most 20 seconds of mono 16 kHz PCM16 WAV audio.');
  }
}
