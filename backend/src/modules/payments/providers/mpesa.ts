import { config } from '../../../config';
import { AppError } from '../../../lib/errors';
import { normalizeKenyanPhone, type PaymentOutcome, type PaymentProvider } from './provider';

/** Safaricom Daraja - Lipa Na M-Pesa Online (STK Push). */

const baseUrl = () =>
  config.mpesa.env === 'production' ? 'https://api.safaricom.co.ke' : 'https://sandbox.safaricom.co.ke';

let cachedToken: { value: string; expiresAt: number } | null = null;

async function accessToken(): Promise<string> {
  if (cachedToken && cachedToken.expiresAt > Date.now()) return cachedToken.value;
  const basic = Buffer.from(`${config.mpesa.consumerKey}:${config.mpesa.consumerSecret}`).toString('base64');
  const res = await fetch(`${baseUrl()}/oauth/v1/generate?grant_type=client_credentials`, {
    headers: { Authorization: `Basic ${basic}` },
  });
  if (!res.ok) throw new Error(`M-Pesa auth failed (${res.status})`);
  const data = (await res.json()) as { access_token: string; expires_in: string };
  cachedToken = { value: data.access_token, expiresAt: Date.now() + (Number(data.expires_in) - 60) * 1000 };
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
  isConfigured: () =>
    Boolean(config.mpesa.consumerKey && config.mpesa.consumerSecret && config.mpesa.shortcode && config.mpesa.passkey),

  async initiate({ amount, phone, reference }) {
    const msisdn = normalizeKenyanPhone(phone ?? '');
    if (!msisdn) throw new AppError(400, 'phone_required');

    const timestamp = darajaTimestamp();
    const password = Buffer.from(`${config.mpesa.shortcode}${config.mpesa.passkey}${timestamp}`).toString('base64');
    const res = await fetch(`${baseUrl()}/mpesa/stkpush/v1/processrequest`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${await accessToken()}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        BusinessShortCode: config.mpesa.shortcode,
        Password: password,
        Timestamp: timestamp,
        TransactionType: config.mpesa.transactionType,
        Amount: Math.ceil(amount),
        PartyA: msisdn,
        PartyB: config.mpesa.partyB || config.mpesa.shortcode,
        PhoneNumber: msisdn,
        CallBackURL: `${config.publicUrl}/api/payments/callbacks/mpesa/${config.mpesa.callbackToken}`,
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
