import { Router } from 'express';
import { z } from 'zod';
import { ah } from '../../lib/http';
import { airtelAccessToken } from '../payments/providers/airtel';
import { checkFlutterwaveKey } from '../payments/providers/flutterwave';
import { mpesaAccessToken } from '../payments/providers/mpesa';
import { getPaymentSettings, paymentSettingsSchema, paymentSettingsView, savePaymentSettings } from '../payments/settings';

/** Settings > Payment methods: gateways and their keys, changed without redeploying. */
export const settingsAdminRouter = Router();

settingsAdminRouter.get(
  '/settings/payments',
  ah(async (_req, res) => {
    res.json(await paymentSettingsView());
  }),
);

settingsAdminRouter.put(
  '/settings/payments',
  ah(async (req, res) => {
    res.json(await savePaymentSettings(paymentSettingsSchema.parse(req.body), req.user!.id));
  }),
);

/** Tries the saved keys against the provider (sign-in only, no money moves). */
settingsAdminRouter.post(
  '/settings/payments/test/:provider',
  ah(async (req, res) => {
    const provider = z.enum(['mpesa', 'airtel', 'flutterwave']).parse(req.params.provider);
    const s = await getPaymentSettings();
    try {
      if (provider === 'mpesa') await mpesaAccessToken(s.mpesa);
      if (provider === 'airtel') await airtelAccessToken(s.airtel);
      if (provider === 'flutterwave' && !(await checkFlutterwaveKey(s.flutterwave.secretKey))) throw new Error('Flutterwave rejected the key');
      res.json({ ok: true });
    } catch (e) {
      res.json({ ok: false, message: (e as Error).message });
    }
  }),
);
