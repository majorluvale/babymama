import 'dotenv/config';
import path from 'node:path';

const env = process.env;
const bool = (value: string | undefined, fallback = false) =>
  value === undefined || value === '' ? fallback : ['1', 'true', 'yes', 'on'].includes(value.toLowerCase());
const list = (value: string | undefined) =>
  (value ?? '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);

const isProduction = env.NODE_ENV === 'production';

export const config = {
  isProduction,
  /** Running as Vercel functions: no long-lived process, read-only disk. */
  serverless: Boolean(env.VERCEL),
  /** Vercel Blob token: when set, uploaded photos go to Blob storage instead of the local disk. */
  blobToken: env.BLOB_READ_WRITE_TOKEN ?? '',
  port: Number(env.PORT ?? 4000),
  publicUrl: (env.PUBLIC_URL ?? 'http://localhost:4000').replace(/\/$/, ''),
  corsOrigins: list(env.CORS_ORIGINS),
  jwtSecret: env.JWT_SECRET ?? 'dev-secret-change-me',
  /** Encrypts the payment keys saved from the admin. Changing it means re-entering those keys. */
  settingsSecret: env.SETTINGS_SECRET || env.JWT_SECRET || 'dev-secret-change-me',
  jwtExpiresInSeconds: Number(env.JWT_EXPIRES_IN_SECONDS ?? 60 * 60 * 24 * 30),
  uploadDir: path.resolve(env.UPLOAD_DIR ?? 'uploads'),
  orderPaymentTimeoutMinutes: Number(env.ORDER_PAYMENT_TIMEOUT_MINUTES ?? 15),
  google: {
    clientIds: list(env.GOOGLE_CLIENT_IDS),
  },
  payments: {
    mock: bool(env.PAYMENTS_MOCK, !isProduction),
    cashOnDelivery: bool(env.CASH_ON_DELIVERY, true),
  },
  mpesa: {
    env: env.MPESA_ENV ?? 'sandbox',
    consumerKey: env.MPESA_CONSUMER_KEY ?? '',
    consumerSecret: env.MPESA_CONSUMER_SECRET ?? '',
    shortcode: env.MPESA_SHORTCODE ?? '',
    passkey: env.MPESA_PASSKEY ?? '',
    transactionType: env.MPESA_TRANSACTION_TYPE ?? 'CustomerPayBillOnline',
    partyB: env.MPESA_PARTY_B ?? '',
    callbackToken: env.MPESA_CALLBACK_TOKEN ?? 'mpesa-callback',
  },
  airtel: {
    env: env.AIRTEL_ENV ?? 'sandbox',
    clientId: env.AIRTEL_CLIENT_ID ?? '',
    clientSecret: env.AIRTEL_CLIENT_SECRET ?? '',
    callbackToken: env.AIRTEL_CALLBACK_TOKEN ?? 'airtel-callback',
  },
  flutterwave: {
    secretKey: env.FLUTTERWAVE_SECRET_KEY ?? '',
    webhookHash: env.FLUTTERWAVE_WEBHOOK_HASH ?? '',
    redirectUrl: env.FLUTTERWAVE_REDIRECT_URL ?? 'https://babymama.co.ke/payment-complete',
  },
  woo: {
    url: (env.WOO_URL ?? '').replace(/\/$/, ''),
    consumerKey: env.WOO_CONSUMER_KEY ?? '',
    consumerSecret: env.WOO_CONSUMER_SECRET ?? '',
    webhookSecret: env.WOO_WEBHOOK_SECRET ?? '',
    pushStock: bool(env.WOO_PUSH_STOCK, true),
    pushProducts: bool(env.WOO_PUSH_PRODUCTS, false),
    pushOrders: bool(env.WOO_PUSH_ORDERS, false),
  },
};

if (isProduction && config.jwtSecret === 'dev-secret-change-me') {
  throw new Error('JWT_SECRET must be set in production');
}
