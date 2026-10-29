import type { PaymentMethod } from '@prisma/client';
import { config } from '../../../config';
import { AppError } from '../../../lib/errors';
import { airtelProvider } from './airtel';
import { flutterwaveProvider } from './flutterwave';
import { mpesaProvider } from './mpesa';
import type { PaymentProvider } from './provider';

const providers: PaymentProvider[] = [mpesaProvider, airtelProvider, flutterwaveProvider];

/** Development provider: accepts every payment a few seconds after it starts. */
export function mockProvider(method: PaymentMethod): PaymentProvider {
  return {
    method,
    name: `${method} (simulation)`,
    isConfigured: () => true,
    async initiate({ paymentId }) {
      return { status: 'PENDING', providerRef: `MOCK-${paymentId}`, message: 'Simulated payment - it will succeed in a few seconds.' };
    },
  };
}

export const isMock = (p: PaymentProvider) => p.name.endsWith('(simulation)');

export function getProvider(method: PaymentMethod): PaymentProvider {
  const real = providers.find((p) => p.method === method);
  if (real?.isConfigured()) return real;
  if (config.payments.mock && method !== 'CASH_ON_DELIVERY') return mockProvider(method);
  throw new AppError(400, 'payment_method_unavailable');
}

export function enabledMethods() {
  const methods: { method: PaymentMethod; name: string; simulated: boolean }[] = [];
  for (const method of ['MPESA', 'AIRTEL_MONEY', 'CARD'] as const) {
    const real = providers.find((p) => p.method === method);
    if (real?.isConfigured()) methods.push({ method, name: real.name, simulated: false });
    else if (config.payments.mock) methods.push({ method, name: real?.name ?? method, simulated: true });
  }
  if (config.payments.cashOnDelivery) methods.push({ method: 'CASH_ON_DELIVERY', name: 'Cash on delivery', simulated: false });
  return methods;
}
