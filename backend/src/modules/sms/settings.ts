import { z } from 'zod';
import { config } from '../../config';
import { prisma } from '../../lib/prisma';
import { decryptSecret, encryptSecret } from '../../lib/secrets';

/**
 * SMS gateway, editable from the admin (Settings > SMS) without redeploying, like the payment gateways.
 * Africa's Talking is the first provider; add others by implementing a send() and registering it.
 */
export interface SmsSettings {
  /** Simulate sending: the code is logged, not really sent (for development / before a provider is set up). */
  mock: boolean;
  /** Alphanumeric sender name or short code shown to the recipient. */
  senderId: string;
  africasTalking: { username: string; apiKey: string };
}

const SECRET_FIELDS = { africasTalking: ['apiKey'] } as const;
const KEY = 'sms';
const CACHE_MS = 30_000;
let cache: { value: SmsSettings; at: number } | null = null;

function defaults(): SmsSettings {
  return {
    mock: config.sms.mock,
    senderId: config.sms.senderId,
    africasTalking: { username: config.sms.africasTalking.username, apiKey: config.sms.africasTalking.apiKey },
  };
}

type Stored = Partial<{ mock: boolean; senderId: string; africasTalking: Partial<SmsSettings['africasTalking']> }>;

function mapSecrets(stored: Stored, fn: (v: string) => string): Stored {
  const out = structuredClone(stored) as Record<string, Record<string, unknown> | unknown>;
  for (const [group, fields] of Object.entries(SECRET_FIELDS)) {
    const section = out[group] as Record<string, unknown> | undefined;
    if (!section) continue;
    for (const f of fields) if (typeof section[f] === 'string' && section[f] !== '') section[f] = fn(section[f] as string);
  }
  return out as Stored;
}

async function readStored(): Promise<Stored> {
  const row = await prisma.setting.findUnique({ where: { key: KEY } });
  return row ? mapSecrets(JSON.parse(row.value) as Stored, decryptSecret) : {};
}

function merge(base: SmsSettings, stored: Stored): SmsSettings {
  return {
    ...base,
    ...(stored.mock !== undefined && { mock: stored.mock }),
    ...(stored.senderId !== undefined && { senderId: stored.senderId }),
    africasTalking: { ...base.africasTalking, ...stored.africasTalking },
  };
}

/** Effective settings, cached 30 s per process (each instance picks up a change within that delay). */
export async function getSmsSettings(): Promise<SmsSettings> {
  if (cache && Date.now() - cache.at < CACHE_MS) return cache.value;
  const value = merge(defaults(), await readStored());
  cache = { value, at: Date.now() };
  return value;
}

/** True once Africa's Talking keys are filled in (or when running in simulation mode). */
export const smsReady = (s: SmsSettings) => s.mock || Boolean(s.africasTalking.username && s.africasTalking.apiKey);

/** What the admin page shows: plain fields, `apiKeySet` flag, never the key itself. */
export async function smsSettingsView() {
  const s = await getSmsSettings();
  return {
    mock: s.mock,
    senderId: s.senderId,
    africasTalking: { username: s.africasTalking.username, apiKeySet: Boolean(s.africasTalking.apiKey) },
    ready: smsReady(s),
  };
}

const text = z.string().trim().max(200);

/** Secrets: omitted = keep the saved value, "" = remove it. */
export const smsSettingsSchema = z.object({
  mock: z.boolean().optional(),
  senderId: z.string().trim().max(20).optional(),
  africasTalking: z.object({ username: text, apiKey: text }).partial().optional(),
});

export async function saveSmsSettings(input: z.infer<typeof smsSettingsSchema>, userId: string) {
  const stored = await readStored();
  const next: Stored = {
    ...stored,
    ...(input.mock !== undefined && { mock: input.mock }),
    ...(input.senderId !== undefined && { senderId: input.senderId }),
    africasTalking: { ...stored.africasTalking, ...input.africasTalking },
  };
  const value = JSON.stringify(mapSecrets(next, encryptSecret));
  await prisma.setting.upsert({ where: { key: KEY }, create: { key: KEY, value, updatedBy: userId }, update: { value, updatedBy: userId } });
  cache = null;
  return smsSettingsView();
}
