import { config } from '../../../config';
import { AppError } from '../../../lib/errors';
import { mpesaReady, type PaymentSettings } from '../settings';
import { normalizeKenyanPhone, type PaymentOutcome, type PaymentProvider } from './provider';

/** Safaricom Daraja - Lipa Na M-Pesa Online (STK Push). */

type MpesaSettings = PaymentSettings['mpesa'];

const baseUrl = (s: MpesaSettings) => (s.env === 'production' ? 'https://api.safaricom.co.ke' : 'https://sandbox.safaricom.co.ke');

/** The token is cached for the keys it was issued for, so new keys saved in the admin are used at once. */
let cachedToken: { value: string; expiresAt: number; keys: string } | null = null;

export async function mpesaAccessToken(s: MpesaSettings): Promise<string> {
  const keys = `${s.env}:${s.consumerKey}:${s.consumerSecret}`;
  if (cachedToken && cachedToken.keys === keys && cachedToken.expiresAt > Date.now()) return cachedToken.value;
  const basic = Buffer.from(`${s.consumerKey}:${s.consumerSecret}`).toString('base64');
  const res = await fetch(`${baseUrl(s)}/oauth/v1/generate?grant_type=client_credentials`, {
    headers: { Authorization: `Basic ${basic}` },
  });
  if (!res.ok) throw new Error(`M-Pesa auth failed (${res.status})`);
  const data = (await res.json()) as { access_token: string; expires_in: string };
  cachedToken = { value: data.access_token, expiresAt: Date.now() + (Number(data.expires_in) - 60) * 1000, keys };
  return cachedToken.value;
}

/** Daraja expects the timestamp in Nairobi time (UTC+3): YYYYMMDDHHmmss. */
export function darajaTimestamp(date = new Date()): string {
  const d = new Date(date.getTime() + 3 * 60 * 60 * 1000);
  const p = (n: number) => String(n).padStart(2, '0');
  return `${d.getUTCFullYear()}${p(d.getUTCMonth() + 1)}${p(d.getUTCDate())}${p(d.getUTCHours())}${p(d.getUTCMinutes())}${p(d.getUTCSeconds())}`;
}

export const mpesaProvider: PaymentProvider = {
  method: 'MPESA',
  name: 'M-Pesa',
  isReady: mpesaReady,

  async initiate({ amount, phone, reference }, settings) {
    const s = settings.mpesa;
    const msisdn = normalizeKenyanPhone(phone ?? '');
    if (!msisdn) throw new AppError(400, 'phone_required');

    const timestamp = darajaTimestamp();
    const password = Buffer.from(`${s.shortcode}${s.passkey}${timestamp}`).toString('base64');
    const res = await fetch(`${baseUrl(s)}/mpesa/stkpush/v1/processrequest`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${await mpesaAccessToken(s)}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        BusinessShortCode: s.shortcode,
        Password: password,
        Timestamp: timestamp,
        TransactionType: s.transactionType,
        Amount: Math.ceil(amount),
        PartyA: msisdn,
        PartyB: s.partyB || s.shortcode,
        PhoneNumber: msisdn,
        CallBackURL: `${config.publicUrl}/api/payments/callbacks/mpesa/${s.callbackToken}`,
        AccountReference: reference.slice(0, 12),
        TransactionDesc: 'Babymama',
      }),
    });
    const data = (await res.json().catch(() => ({}))) as Record<string, string | undefined>;
    if (!res.ok || data.ResponseCode !== '0') {
      return { status: 'FAILED', message: data.errorMessage ?? data.ResponseDescription ?? 'STK push failed', raw: data };
    }
    return { status: 'PENDING', providerRef: data.CheckoutRequestID, message: data.CustomerMessage, raw: data };
  },
};

interface StkCallback {
  Body?: {
    stkCallback?: {
      CheckoutRequestID: string;
      ResultCode: number | string;
      ResultDesc: string;
      CallbackMetadata?: { Item: { Name: string; Value?: string | number }[] };
    };
  };
}

export function parseMpesaCallback(body: unknown): (PaymentOutcome & { providerRef: string }) | null {
  const cb = (body as StkCallback)?.Body?.stkCallback;
  if (!cb?.CheckoutRequestID) return null;
  const meta = new Map((cb.CallbackMetadata?.Item ?? []).map((i) => [i.Name, i.Value]));
  const amount = meta.get('Amount');
  return {
    providerRef: cb.CheckoutRequestID,
    success: Number(cb.ResultCode) === 0,
    receipt: meta.get('MpesaReceiptNumber')?.toString(),
    amount: amount === undefined ? undefined : Number(amount),
    message: cb.ResultDesc,
    raw: body,
  };
}
