import type { PaymentMethod } from '@prisma/client';

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
  isConfigured(): boolean;
  initiate(input: InitiateInput): Promise<InitiateResult>;
}

/** Normalizes Kenyan numbers to 2547XXXXXXXX / 2541XXXXXXXX. Returns null if invalid. */
export function normalizeKenyanPhone(input: string): string | null {
  const digits = input.replace(/\D/g, '');
  if (/^254[17]\d{8}$/.test(digits)) return digits;
  if (/^0[17]\d{8}$/.test(digits)) return `254${digits.slice(1)}`;
  if (/^[17]\d{8}$/.test(digits)) return `254${digits}`;
  return null;
}
