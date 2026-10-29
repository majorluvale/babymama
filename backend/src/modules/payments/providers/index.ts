import type { PaymentMethod } from '@prisma/client';
import { AppError } from '../../../lib/errors';
import { getPaymentSettings, type PaymentSettings } from '../settings';
import { airtelProvider } from './airtel';
import { flutterwaveProvider } from './flutterwave';
import { mpesaProvider } from './mpesa';
import type { PaymentProvider } from './provider';

const providers: PaymentProvider[] = [mpesaProvider, airtelProvider, flutterwaveProvider];

/** Simulated payments: accepted a few seconds after they start. */
export function mockProvider(method: PaymentMethod): PaymentProvider {
  return {
    method,
    name: `${method} (simulation)`,
    isReady: () => true,
    async initiate({ paymentId }) {
      return { status: 'PENDING', providerRef: `MOCK-${paymentId}`, message: 'Simulated payment - it will succeed in a few seconds.' };
    },
  };
}

export const isMock = (p: PaymentProvider) => p.name.endsWith('(simulation)');

/** The provider for a method with the current settings (real when it is set up, otherwise simulated in test mode). */
export async function getProvider(method: PaymentMethod): Promise<{ provider: PaymentProvider; settings: PaymentSettings }> {
  const settings = await getPaymentSettings();
  const real = providers.find((p) => p.method === method);
  if (real?.isReady(settings)) return { provider: real, settings };
  if (settings.mock && method !== 'CASH_ON_DELIVERY') return { provider: mockProvider(method), settings };
  throw new AppError(400, 'payment_method_unavailable');
}

export async function enabledMethods() {
  const settings = await getPaymentSettings();
  const methods: { method: PaymentMethod; name: string; simulated: boolean }[] = [];
  for (const method of ['MPESA', 'AIRTEL_MONEY', 'CARD'] as const) {
    const real = providers.find((p) => p.method === method);
    if (real?.isReady(settings)) methods.push({ method, name: real.name, simulated: false });
    else if (settings.mock) methods.push({ method, name: real?.name ?? method, simulated: true });
  }
  if (settings.cashOnDelivery) methods.push({ method: 'CASH_ON_DELIVERY', name: 'Cash on delivery', simulated: false });
  return methods;
}
