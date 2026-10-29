import { config } from '../../../config';
import type { PaymentOutcome, PaymentProvider } from './provider';

/** Flutterwave Standard (hosted checkout): cards, and M-Pesa as a fallback. */

const API = 'https://api.flutterwave.com/v3';
const headers = () => ({ Authorization: `Bearer ${config.flutterwave.secretKey}`, 'Content-Type': 'application/json' });

export const flutterwaveProvider: PaymentProvider = {
  method: 'CARD',
  name: 'Card (Flutterwave)',
  isConfigured: () => Boolean(config.flutterwave.secretKey),

  async initiate({ paymentId, amount, email, phone, name, reference }) {
    const res = await fetch(`${API}/payments`, {
      method: 'POST',
      headers: headers(),
      body: JSON.stringify({
        tx_ref: paymentId,
        amount,
        currency: 'KES',
        redirect_url: config.flutterwave.redirectUrl,
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

/** Never trust the webhook body alone: re-fetch the transaction from Flutterwave. */
export async function verifyFlutterwaveTransaction(
  transactionId: string | number,
): Promise<(PaymentOutcome & { providerRef: string }) | null> {
  const res = await fetch(`${API}/transactions/${transactionId}/verify`, { headers: headers() });
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
