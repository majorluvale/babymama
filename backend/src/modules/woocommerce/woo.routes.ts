import crypto from 'node:crypto';
import { Router } from 'express';
import { config } from '../../config';
import { AppError } from '../../lib/errors';
import { ah } from '../../lib/http';
import { prisma } from '../../lib/prisma';
import { wooEnabled, type WooProduct } from './woo.client';
import { archiveFromWoo, importAllFromWoo, pushStockToWoo, upsertFromWoo } from './woo.sync';

/**
 * Public webhook endpoint. In WooCommerce > Settings > Advanced > Webhooks create
 * "Product created", "Product updated", "Product deleted" and "Product restored" webhooks pointing to
 *   {PUBLIC_URL}/api/woocommerce/webhook   with the secret = WOO_WEBHOOK_SECRET.
 */
export const wooWebhookRouter = Router();

wooWebhookRouter.post(
  '/webhook',
  ah(async (req, res) => {
    const signature = req.header('x-wc-webhook-signature');
    const topic = req.header('x-wc-webhook-topic') ?? '';
    // WooCommerce sends an unsigned "ping" when the webhook is saved: acknowledge it.
    if (!signature || !topic) {
      res.json({ ok: true });
      return;
    }
    if (!config.woo.webhookSecret) throw new AppError(503, 'woocommerce_not_configured');
    const expected = crypto.createHmac('sha256', config.woo.webhookSecret).update(req.rawBody ?? Buffer.alloc(0)).digest('base64');
    const a = Buffer.from(signature);
    const b = Buffer.from(expected);
    if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) throw new AppError(401, 'invalid_signature');

    if (topic === 'product.created' || topic === 'product.updated' || topic === 'product.restored') {
      await upsertFromWoo(req.body as WooProduct);
    } else if (topic === 'product.deleted') {
      await archiveFromWoo(Number((req.body as { id: number }).id));
    }
    res.json({ ok: true });
  }),
);

/** Admin tools, mounted under /admin/woocommerce. */
export const wooAdminRouter = Router();

wooAdminRouter.get(
  '/status',
  ah(async (_req, res) => {
    res.json({
      enabled: wooEnabled(),
      url: config.woo.url || null,
      webhookUrl: `${config.publicUrl}/api/woocommerce/webhook`,
      webhookSecretSet: Boolean(config.woo.webhookSecret),
      pushStock: config.woo.pushStock,
      pushProducts: config.woo.pushProducts,
      pushOrders: config.woo.pushOrders,
      linkedProducts: await prisma.product.count({ where: { wooId: { not: null } } }),
    });
  }),
);

wooAdminRouter.post(
  '/import',
  ah(async (_req, res) => {
    if (!wooEnabled()) throw new AppError(400, 'woocommerce_not_configured');
    res.json(await importAllFromWoo());
  }),
);

wooAdminRouter.post(
  '/push-stock',
  ah(async (_req, res) => {
    if (!wooEnabled()) throw new AppError(400, 'woocommerce_not_configured');
    const linked = await prisma.product.findMany({ where: { wooId: { not: null } }, select: { id: true } });
    await pushStockToWoo(linked.map((p) => p.id));
    res.json({ pushed: linked.length });
  }),
);
