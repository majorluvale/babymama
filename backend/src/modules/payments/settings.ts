import crypto from 'node:crypto';
import { z } from 'zod';
import { config } from '../../config';
import { prisma } from '../../lib/prisma';
import { decryptSecret, encryptSecret } from '../../lib/secrets';

/**
 * Payment gateways, editable from the admin (Settings > Payment methods) without redeploying.
 * Values saved in the database override the environment variables, which stay as defaults.
 */
export interface PaymentSettings {
  /** Simulated payments for the methods that are not set up (tests). */
  mock: boolean;
  cashOnDelivery: boolean;
  mpesa: {
    enabled: boolean;
    env: 'sandbox' | 'production';
    consumerKey: string;
    consumerSecret: string;
    shortcode: string;
    passkey: string;
    transactionType: 'CustomerPayBillOnline' | 'CustomerBuyGoodsOnline';
    partyB: string;
    callbackToken: string;
  };
  airtel: { enabled: boolean; env: 'sandbox' | 'production'; clientId: string; clientSecret: string; callbackToken: string };
  flutterwave: { enabled: boolean; secretKey: string; webhookHash: string; redirectUrl: string };
}

/** Fields never sent back to the admin app: it only learns whether they are set. */
const SECRET_FIELDS = {
  mpesa: ['consumerSecret', 'passkey', 'callbackToken'],
  airtel: ['clientSecret', 'callbackToken'],
  flutterwave: ['secretKey', 'webhookHash'],
} as const;

const KEY = 'payments';
const CACHE_MS = 30_000;
let cache: { value: PaymentSettings; at: number } | null = null;

function defaults(): PaymentSettings {
  return {
    mock: config.payments.mock,
    cashOnDelivery: config.payments.cashOnDelivery,
    mpesa: {
      enabled: true,
      env: config.mpesa.env === 'production' ? 'production' : 'sandbox',
      consumerKey: config.mpesa.consumerKey,
      consumerSecret: config.mpesa.consumerSecret,
      shortcode: config.mpesa.shortcode,
      passkey: config.mpesa.passkey,
      transactionType: config.mpesa.transactionType === 'CustomerBuyGoodsOnline' ? 'CustomerBuyGoodsOnline' : 'CustomerPayBillOnline',
      partyB: config.mpesa.partyB,
      callbackToken: config.mpesa.callbackToken,
    },
    airtel: {
      enabled: true,
      env: config.airtel.env === 'production' ? 'production' : 'sandbox',
      clientId: config.airtel.clientId,
      clientSecret: config.airtel.clientSecret,
      callbackToken: config.airtel.callbackToken,
    },
    flutterwave: {
      enabled: true,
      secretKey: config.flutterwave.secretKey,
      webhookHash: config.flutterwave.webhookHash,
      redirectUrl: config.flutterwave.redirectUrl,
    },
  };
}

type Stored = Partial<{ [K in keyof PaymentSettings]: PaymentSettings[K] extends object ? Partial<PaymentSettings[K]> : PaymentSettings[K] }>;

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

function merge(base: PaymentSettings, stored: Stored): PaymentSettings {
  return {
    ...base,
    ...(stored.mock !== undefined && { mock: stored.mock }),
    ...(stored.cashOnDelivery !== undefined && { cashOnDelivery: stored.cashOnDelivery }),
    mpesa: { ...base.mpesa, ...stored.mpesa },
    airtel: { ...base.airtel, ...stored.airtel },
    flutterwave: { ...base.flutterwave, ...stored.flutterwave },
  };
}

/** Effective settings, cached 30 s per process (each Vercel instance picks up a change within that delay). */
export async function getPaymentSettings(): Promise<PaymentSettings> {
  if (cache && Date.now() - cache.at < CACHE_MS) return cache.value;
  const value = merge(defaults(), await readStored());
  cache = { value, at: Date.now() };
  return value;
}

export const mpesaReady = (s: PaymentSettings) =>
  s.mpesa.enabled && Boolean(s.mpesa.consumerKey && s.mpesa.consumerSecret && s.mpesa.shortcode && s.mpesa.passkey);
export const airtelReady = (s: PaymentSettings) => s.airtel.enabled && Boolean(s.airtel.clientId && s.airtel.clientSecret);
export const flutterwaveReady = (s: PaymentSettings) => s.flutterwave.enabled && Boolean(s.flutterwave.secretKey);

/** What the admin page shows: plain fields, `xxxSet` flags for secrets, and the URLs to give each provider. */
export async function paymentSettingsView() {
  const s = await getPaymentSettings();
  const secretFlags = (group: keyof typeof SECRET_FIELDS) => {
    const section = s[group] as unknown as Record<string, string>;
    return Object.fromEntries(SECRET_FIELDS[group].filter((f) => f !== 'callbackToken').map((f) => [`${f}Set`, Boolean(section[f])]));
  };
  const strip = <T extends object>(section: T, group: keyof typeof SECRET_FIELDS) =>
    Object.fromEntries(Object.entries(section).filter(([k]) => !(SECRET_FIELDS[group] as readonly string[]).includes(k)));
  return {
    mock: s.mock,
    cashOnDelivery: s.cashOnDelivery,
    mpesa: {
      ...strip(s.mpesa, 'mpesa'),
      ...secretFlags('mpesa'),
      ready: mpesaReady(s),
      callbackUrl: `${config.publicUrl}/api/payments/callbacks/mpesa/${s.mpesa.callbackToken}`,
    },
    airtel: {
      ...strip(s.airtel, 'airtel'),
      ...secretFlags('airtel'),
      ready: airtelReady(s),
      callbackUrl: `${config.publicUrl}/api/payments/callbacks/airtel/${s.airtel.callbackToken}`,
    },
    flutterwave: {
      ...strip(s.flutterwave, 'flutterwave'),
      ...secretFlags('flutterwave'),
      ready: flutterwaveReady(s),
      webhookUrl: `${config.publicUrl}/api/payments/callbacks/flutterwave`,
    },
  };
}

const env = z.enum(['sandbox', 'production']);
/** Secrets: omitted = keep the saved value, "" = remove it. */
const text = z.string().trim().max(500);

export const paymentSettingsSchema = z.object({
  mock: z.boolean().optional(),
  cashOnDelivery: z.boolean().optional(),
  mpesa: z
    .object({
      enabled: z.boolean(),
      env,
      consumerKey: text,
      consumerSecret: text,
      shortcode: z.string().trim().regex(/^\d{0,10}$/),
      passkey: text,
      transactionType: z.enum(['CustomerPayBillOnline', 'CustomerBuyGoodsOnline']),
      partyB: z.string().trim().regex(/^\d{0,10}$/),
    })
    .partial()
    .optional(),
  airtel: z.object({ enabled: z.boolean(), env, clientId: text, clientSecret: text }).partial().optional(),
  flutterwave: z
    .object({ enabled: z.boolean(), secretKey: text, webhookHash: text, redirectUrl: z.string().trim().url() })
    .partial()
    .optional(),
});

export async function savePaymentSettings(input: z.infer<typeof paymentSettingsSchema>, userId: string) {
  const stored = await readStored();
  const next: Stored = {
    ...stored,
    ...(input.mock !== undefined && { mock: input.mock }),
    ...(input.cashOnDelivery !== undefined && { cashOnDelivery: input.cashOnDelivery }),
    mpesa: { ...stored.mpesa, ...input.mpesa },
    airtel: { ...stored.airtel, ...input.airtel },
    flutterwave: { ...stored.flutterwave, ...input.flutterwave },
  };
  // Callback URLs carry a random token so nobody can fake a "payment received" call.
  const current = merge(defaults(), next);
  if (!next.mpesa!.callbackToken && current.mpesa.callbackToken === 'mpesa-callback') next.mpesa!.callbackToken = crypto.randomBytes(16).toString('hex');
  if (!next.airtel!.callbackToken && current.airtel.callbackToken === 'airtel-callback') next.airtel!.callbackToken = crypto.randomBytes(16).toString('hex');

  const value = JSON.stringify(mapSecrets(next, encryptSecret));
  await prisma.setting.upsert({ where: { key: KEY }, create: { key: KEY, value, updatedBy: userId }, update: { value, updatedBy: userId } });
  cache = null;
  return paymentSettingsView();
}
