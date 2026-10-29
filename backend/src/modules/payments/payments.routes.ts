import { Router } from 'express';
import { PaymentMethod } from '@prisma/client';
import { z } from 'zod';
import { AppError } from '../../lib/errors';
import { ah } from '../../lib/http';
import { requireAuth } from '../../middleware/auth';
import { getPaymentForUser, initiatePayment, settlePayment } from './payments.service';
import { enabledMethods } from './providers';
import { getPaymentSettings } from './settings';
import { parseAirtelCallback } from './providers/airtel';
import { verifyFlutterwaveTransaction } from './providers/flutterwave';
import { parseMpesaCallback } from './providers/mpesa';

export const paymentsRouter = Router();

paymentsRouter.get(
  '/methods',
  ah(async (_req, res) => {
    res.json(await enabledMethods());
  }),
);

const initiateSchema = z.object({
  method: z.nativeEnum(PaymentMethod).optional(),
  phone: z.string().trim().max(20).optional(),
});

/** Starts a payment: M-Pesa / Airtel send a PIN prompt to the phone, cards return a checkout URL. */
paymentsRouter.post(
  '/orders/:orderId',
  requireAuth,
  ah(async (req, res) => {
    const body = initiateSchema.parse(req.body);
    res.status(201).json(await initiatePayment(req.user!.id, req.params.orderId, body));
  }),
);

/** Polled by the apps while the customer approves the payment. */
paymentsRouter.get(
  '/:id',
  requireAuth,
  ah(async (req, res) => {
    res.json(await getPaymentForUser(req.params.id, req.user!));
  }),
);

// ---- Provider callbacks (public, protected by secret tokens / signatures) ----

paymentsRouter.post(
  '/callbacks/mpesa/:token',
  ah(async (req, res) => {
    if (req.params.token !== (await getPaymentSettings()).mpesa.callbackToken) throw new AppError(403, 'forbidden');
    const outcome = parseMpesaCallback(req.body);
    if (outcome) await settlePayment({ providerRef: outcome.providerRef }, outcome);
    res.json({ ResultCode: 0, ResultDesc: 'Accepted' });
  }),
);

paymentsRouter.post(
  '/callbacks/airtel/:token',
  ah(async (req, res) => {
    if (req.params.token !== (await getPaymentSettings()).airtel.callbackToken) throw new AppError(403, 'forbidden');
    const outcome = parseAirtelCallback(req.body);
    if (outcome) await settlePayment({ providerRef: outcome.providerRef }, outcome);
    res.json({ ok: true });
  }),
);

paymentsRouter.post(
  '/callbacks/flutterwave',
  ah(async (req, res) => {
    const { flutterwave } = await getPaymentSettings();
    if (!flutterwave.webhookHash || req.header('verif-hash') !== flutterwave.webhookHash) {
      throw new AppError(401, 'invalid_signature');
    }
    const id = (req.body as { data?: { id?: number } })?.data?.id;
    if (id) {
      const outcome = await verifyFlutterwaveTransaction(id, flutterwave.secretKey);
      if (outcome) await settlePayment({ providerRef: outcome.providerRef }, outcome);
    }
    res.json({ ok: true });
  }),
);
