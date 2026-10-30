import type { PaymentMethod } from '@prisma/client';
import { normalizeKenyanPhone } from '../../../lib/phone';
import type { PaymentSettings } from '../settings';

export { normalizeKenyanPhone };

export interface InitiateInput {
  paymentId: string;
  /** Human readable order reference, e.g. BM-000123 */
  reference: string;
  amount: number;
  phone?: string;
  email?: string;
  name?: string;
}

export interface InitiateResult {
  status: 'PENDING' | 'SUCCESS' | 'FAILED';
  providerRef?: string;
  /** Hosted checkout page (cards). */
  redirectUrl?: string;
  message?: string;
  raw?: unknown;
}

/** Outcome reported asynchronously by a provider callback / webhook. */
export interface PaymentOutcome {
  success: boolean;
  receipt?: string;
  amount?: number;
  message?: string;
  raw?: unknown;
}

/**
 * A mobile-money or card provider. To add a new one (e.g. Pesapal, T-Kash, Equitel),
 * implement this interface, register it in providers/index.ts and add a callback route.
 */
export interface PaymentProvider {
  method: PaymentMethod;
  name: string;
  /** Enabled in the admin and all its keys are filled in. */
  isReady(settings: PaymentSettings): boolean;
  initiate(input: InitiateInput, settings: PaymentSettings): Promise<InitiateResult>;
}
