import type { IncomingMessage } from 'node:http';
import cors from 'cors';
import express, { Router } from 'express';
import helmet from 'helmet';
import morgan from 'morgan';
import { config } from './config';

// Keep the secret callback token out of the access logs (it sits in the URL path).
morgan.token('url', (req: express.Request) =>
  (req.originalUrl || req.url).replace(/(\/callbacks\/(?:mpesa|airtel)\/)[^/?]+/, '$1***'),
);
import { errorHandler, notFoundHandler } from './lib/errors';
import { adminRouter } from './modules/admin';
import { authRouter } from './modules/auth/auth.routes';
import { catalogRouter } from './modules/catalog/catalog.routes';
import { driverRouter } from './modules/delivery/driver.routes';
import { ordersRouter } from './modules/orders/orders.routes';
import { expireUnpaidOrders } from './modules/orders/orders.service';
import { paymentsRouter } from './modules/payments/payments.routes';
import { supportRouter } from './modules/support/support.routes';
import { uploadsRouter } from './modules/uploads/uploads.routes';
import { wooWebhookRouter } from './modules/woocommerce/woo.routes';

let lastExpiry = 0;

/** Runs the unpaid-order expiry at most once a minute per function instance, before the request. */
async function expireUnpaidOrdersThrottled(_req: express.Request, _res: express.Response, next: express.NextFunction) {
  if (Date.now() - lastExpiry > 60_000) {
    lastExpiry = Date.now();
    await expireUnpaidOrders().catch((e) => console.error('[jobs] expireUnpaidOrders', e));
  }
  next();
}

export function createApp() {
  const app = express();
  app.set('trust proxy', 1);
  app.use(helmet({ crossOriginResourcePolicy: { policy: 'cross-origin' } }));
  // Reflect any origin only in development. In production, the shop/admin origins must be
  // listed in CORS_ORIGINS; an empty list then blocks cross-site requests instead of allowing all.
  app.use(cors({ origin: config.corsOrigins.length ? config.corsOrigins : !config.isProduction }));
  app.use(
    express.json({
      limit: '2mb',
      // Keep the raw body for WooCommerce webhook signatures.
      verify: (req, _res, buf) => {
        (req as IncomingMessage & { rawBody?: Buffer }).rawBody = buf;
      },
    }),
  );
  app.use(morgan(config.isProduction ? 'combined' : 'dev'));
  app.use('/uploads', express.static(config.uploadDir, { maxAge: '7d' }));
  // Serverless: no timer between requests, so unpaid orders are expired while handling traffic instead.
  if (config.serverless) app.use(expireUnpaidOrdersThrottled);

  app.get('/health', (_req, res) => {
    res.json({ ok: true, service: 'babymama-api', time: new Date().toISOString() });
  });

  const api = Router();
  api.use('/auth', authRouter);
  api.use('/orders', ordersRouter);
  api.use('/payments', paymentsRouter);
  api.use('/support', supportRouter);
  api.use('/driver', driverRouter);
  api.use('/uploads', uploadsRouter);
  api.use('/woocommerce', wooWebhookRouter);
  api.use('/admin', adminRouter);
  api.use(catalogRouter);
  app.use('/api', api);

  app.use(notFoundHandler);
  app.use(errorHandler);
  return app;
}
