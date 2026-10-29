import { flutterwaveReady, type PaymentSettings } from '../settings';
import type { PaymentOutcome, PaymentProvider } from './provider';

/** Flutterwave Standard (hosted checkout): cards, and M-Pesa as a fallback. */

const API = 'https://api.flutterwave.com/v3';
const headers = (secretKey: string) => ({ Authorization: `Bearer ${secretKey}`, 'Content-Type': 'application/json' });

export const flutterwaveProvider: PaymentProvider = {
  method: 'CARD',
  name: 'Card (Flutterwave)',
  isReady: flutterwaveReady,

  async initiate({ paymentId, amount, email, phone, name, reference }, settings) {
    const s = settings.flutterwave;
    const res = await fetch(`${API}/payments`, {
      method: 'POST',
      headers: headers(s.secretKey),
      body: JSON.stringify({
        tx_ref: paymentId,
        amount,
        currency: 'KES',
        redirect_url: s.redirectUrl,
        payment_options: 'card,mpesa',
        customer: { email, phonenumber: phone, name },
        customizations: { title: 'Babymama', description: `Order ${reference}` },
      }),
    });
    const data = (await res.json().catch(() => ({}))) as { status?: string; message?: string; data?: { link?: string } };
    if (!res.ok || data.status !== 'success' || !data.data?.link) {
      return { status: 'FAILED', message: data.message ?? 'Card payment could not start', raw: data };
    }
    return { status: 'PENDING', providerRef: paymentId, redirectUrl: data.data.link, raw: data };
  },
};

/** Checks a secret key with a read-only call (KES balance). */
export async function checkFlutterwaveKey(secretKey: string): Promise<boolean> {
  const res = await fetch(`${API}/balances/KES`, { headers: headers(secretKey) });
  return res.ok;
}

/** Never trust the webhook body alone: re-fetch the transaction from Flutterwave. */
export async function verifyFlutterwaveTransaction(
  transactionId: string | number,
  secretKey: string,
): Promise<(PaymentOutcome & { providerRef: string }) | null> {
  const res = await fetch(`${API}/transactions/${transactionId}/verify`, { headers: headers(secretKey) });
  if (!res.ok) return null;
  const body = (await res.json()) as {
    data?: { status: string; tx_ref: string; amount: number; currency: string; flw_ref?: string };
  };
  const d = body.data;
  if (!d?.tx_ref) return null;
  return {
    providerRef: d.tx_ref,
    success: d.status === 'successful' && d.currency === 'KES',
    amount: d.amount,
    receipt: d.flw_ref,
    message: d.status,
    raw: body,
  };
}
