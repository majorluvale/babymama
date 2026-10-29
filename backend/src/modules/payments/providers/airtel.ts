import { config } from '../../../config';
import { AppError } from '../../../lib/errors';
import { normalizeKenyanPhone, type PaymentOutcome, type PaymentProvider } from './provider';

/** Airtel Money Kenya - Airtel Africa Open API (USSD push collection). */

const baseUrl = () =>
  config.airtel.env === 'production' ? 'https://openapi.airtel.africa' : 'https://openapiuat.airtel.africa';

let cachedToken: { value: string; expiresAt: number } | null = null;

async function accessToken(): Promise<string> {
  if (cachedToken && cachedToken.expiresAt > Date.now()) return cachedToken.value;
  const res = await fetch(`${baseUrl()}/auth/oauth2/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Accept: '*/*' },
    body: JSON.stringify({
      client_id: config.airtel.clientId,
      client_secret: config.airtel.clientSecret,
      grant_type: 'client_credentials',
    }),
  });
  if (!res.ok) throw new Error(`Airtel auth failed (${res.status})`);
  const data = (await res.json()) as { access_token: string; expires_in: number | string };
  cachedToken = { value: data.access_token, expiresAt: Date.now() + (Number(data.expires_in) - 60) * 1000 };
  return cachedToken.value;
}

export const airtelProvider: PaymentProvider = {
  method: 'AIRTEL_MONEY',
  name: 'Airtel Money',
  isConfigured: () => Boolean(config.airtel.clientId && config.airtel.clientSecret),

  async initiate({ amount, phone, reference, paymentId }) {
    const msisdn = normalizeKenyanPhone(phone ?? '');
    if (!msisdn) throw new AppError(400, 'phone_required');

    const res = await fetch(`${baseUrl()}/merchant/v1/payments/`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${await accessToken()}`,
        'Content-Type': 'application/json',
        Accept: '*/*',
        'X-Country': 'KE',
        'X-Currency': 'KES',
      },
      body: JSON.stringify({
        reference,
        subscriber: { country: 'KE', currency: 'KES', msisdn: msisdn.slice(3) },
        transaction: { amount: Math.ceil(amount), country: 'KE', currency: 'KES', id: paymentId },
      }),
    });
    const data = (await res.json().catch(() => ({}))) as { status?: { success?: boolean; message?: string } };
    if (!res.ok || !data.status?.success) {
      return { status: 'FAILED', message: data.status?.message ?? 'Airtel Money request failed', raw: data };
    }
    return { status: 'PENDING', providerRef: paymentId, message: data.status.message, raw: data };
  },
};

interface AirtelCallback {
  transaction?: { id: string; message?: string; status_code?: string; airtel_money_id?: string };
}

export function parseAirtelCallback(body: unknown): (PaymentOutcome & { providerRef: string }) | null {
  const tx = (body as AirtelCallback)?.transaction;
  if (!tx?.id) return null;
  return {
    providerRef: tx.id,
    success: tx.status_code === 'TS',
    receipt: tx.airtel_money_id,
    message: tx.message,
    raw: body,
  };
}
