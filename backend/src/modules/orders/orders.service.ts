import crypto from 'node:crypto';
import type { PaymentMethod, Prisma } from '@prisma/client';
import { config } from '../../config';
import { orderDto, orderInclude } from '../../lib/dto';
import { AppError, notFound } from '../../lib/errors';
import { prisma } from '../../lib/prisma';
import { releaseOrderStock, takeStock } from '../stock/stock.service';
import { getPaymentSettings } from '../payments/settings';
import { pushStockToWoo } from '../woocommerce/woo.sync';
import { computeTotals, type PriceLine } from './pricing';

type Db = Prisma.TransactionClient;

export interface CartInput {
  items: { productId: string; quantity: number }[];
  bundles: { bundleId: string; quantity: number }[];
}

export interface CheckoutInput extends CartInput {
  zoneId: string;
  paymentMethod: PaymentMethod;
  address: {
    recipientName: string;
    phone: string;
    street: string;
    landmark?: string | null;
    lat?: number | null;
    lng?: number | null;
  };
  notes?: string;
  saveAddress?: boolean;
}

interface ResolvedLine extends PriceLine {
  productId?: string;
  bundleId?: string;
  sellerId?: string | null;
  title: string;
  imageUrl: string | null;
  available: number;
  components?: { productId: string; quantity: number }[];
}

function isLive(b: { active: boolean; startsAt: Date | null; endsAt: Date | null }, now = new Date()) {
  return b.active && (!b.startsAt || b.startsAt <= now) && (!b.endsAt || b.endsAt >= now);
}

/** Validates the cart against current prices and stock. Does not change anything. */
async function resolveCart(db: Db, cart: CartInput): Promise<ResolvedLine[]> {
  const merged = new Map<string, number>();
  for (const i of cart.items) merged.set(i.productId, (merged.get(i.productId) ?? 0) + i.quantity);
  if (merged.size === 0 && cart.bundles.length === 0) throw new AppError(400, 'empty_order');

  const lines: ResolvedLine[] = [];

  if (merged.size) {
    const products = await db.product.findMany({
      where: { id: { in: [...merged.keys()] } },
      include: { images: { orderBy: { position: 'asc' }, take: 1 } },
    });
    const byId = new Map(products.map((p) => [p.id, p]));
    for (const [productId, quantity] of merged) {
      const p = byId.get(productId);
      if (!p || p.status !== 'ACTIVE') throw new AppError(409, 'product_unavailable', { productId });
      if (p.stock < quantity) throw new AppError(409, 'out_of_stock', { productId, available: p.stock });
      lines.push({
        kind: 'product',
        productId,
        sellerId: p.sellerId,
        title: p.title,
        imageUrl: p.images[0]?.url ?? null,
        unitPrice: p.price,
        quantity,
        available: p.stock,
      });
    }
  }

  if (cart.bundles.length) {
    const bundles = await db.bundle.findMany({
      where: { id: { in: cart.bundles.map((b) => b.bundleId) } },
      include: { items: { include: { product: { include: { images: { orderBy: { position: 'asc' }, take: 1 } } } } } },
    });
    const byId = new Map(bundles.map((b) => [b.id, b]));
    for (const { bundleId, quantity } of cart.bundles) {
      const b = byId.get(bundleId);
      if (!b || !isLive(b) || b.items.length === 0) throw new AppError(409, 'bundle_unavailable', { bundleId });
      const available = Math.min(
        ...b.items.map((i) => (i.product.status === 'ACTIVE' ? Math.floor(i.product.stock / i.quantity) : 0)),
      );
      if (available < quantity) throw new AppError(409, 'out_of_stock', { bundleId, available });
      lines.push({
        kind: 'bundle',
        bundleId,
        title: b.title,
        imageUrl: b.imageUrl ?? b.items[0]?.product.images[0]?.url ?? null,
        unitPrice: b.price,
        quantity,
        available,
        components: b.items.map((i) => ({ productId: i.productId, quantity: i.quantity })),
      });
    }
  }
  return lines;
}

const activeTiers = () => prisma.discountTier.findMany({ where: { active: true } });

const lineDto = (l: ResolvedLine) => ({
  kind: l.kind,
  productId: l.productId ?? null,
  bundleId: l.bundleId ?? null,
  title: l.title,
  imageUrl: l.imageUrl,
  unitPrice: l.unitPrice,
  quantity: l.quantity,
  available: l.available,
});

export async function quoteCart(cart: CartInput, zoneId?: string) {
  const [lines, tiers, zone] = await Promise.all([
    resolveCart(prisma, cart),
    activeTiers(),
    zoneId ? prisma.deliveryZone.findUnique({ where: { id: zoneId } }) : Promise.resolve(null),
  ]);
  return { ...computeTotals(lines, tiers, zone?.fee ?? 0), lines: lines.map(lineDto) };
}

export const generateDeliveryCode = () => crypto.randomInt(0, 10000).toString().padStart(4, '0');

export async function createOrder(userId: string, input: CheckoutInput) {
  const zone = await prisma.deliveryZone.findUnique({ where: { id: input.zoneId } });
  if (!zone?.active) throw new AppError(400, 'zone_unavailable');
  if (input.paymentMethod === 'CASH_ON_DELIVERY' && !(await getPaymentSettings()).cashOnDelivery) {
    throw new AppError(400, 'payment_method_unavailable');
  }
  const tiers = await activeTiers();
  const isCod = input.paymentMethod === 'CASH_ON_DELIVERY';
  const touched = new Set<string>();

  const order = await prisma.$transaction(async (tx) => {
    const lines = await resolveCart(tx, input);
    const totals = computeTotals(lines, tiers, zone.fee);

    const created = await tx.order.create({
      data: {
        userId,
        zoneId: zone.id,
        paymentMethod: input.paymentMethod,
        status: isCod ? 'CONFIRMED' : 'PENDING_PAYMENT',
        paymentStatus: 'UNPAID',
        subtotal: totals.subtotal,
        discount: totals.discount,
        discountPercent: totals.discountPercent,
        deliveryFee: totals.deliveryFee,
        total: totals.total,
        address: { ...input.address, zone: zone.name } as Prisma.InputJsonValue,
        notes: input.notes,
        deliveryCode: generateDeliveryCode(),
        expiresAt: isCod ? null : new Date(Date.now() + config.orderPaymentTimeoutMinutes * 60_000),
        items: {
          create: lines.map((l) => ({
            productId: l.productId ?? null,
            bundleId: l.bundleId ?? null,
            sellerId: l.sellerId ?? null,
            title: l.title,
            imageUrl: l.imageUrl,
            unitPrice: l.unitPrice,
            quantity: l.quantity,
          })),
        },
        delivery: { create: {} },
      },
    });

    // Reserve stock right away: unpaid orders release it when they expire.
    for (const l of lines) {
      if (l.kind === 'product' && l.productId) {
        await takeStock(tx, l.productId, l.quantity, { orderId: created.id, userId });
        touched.add(l.productId);
      }
      for (const c of l.components ?? []) {
        await takeStock(tx, c.productId, c.quantity * l.quantity, { orderId: created.id, userId, reason: `Bundle: ${l.title}` });
        touched.add(c.productId);
      }
    }
    return created;
  });

  if (input.saveAddress) {
    await prisma.address
      .create({ data: { userId, zoneId: zone.id, ...input.address, landmark: input.address.landmark ?? null } })
      .catch((e) => console.warn('[orders] could not save address', e));
  }
  void pushStockToWoo([...touched]);
  return getOrder(order.id, { revealCode: true });
}

export async function getOrder(id: string, opts: { revealCode?: boolean } = {}) {
  const order = await prisma.order.findUnique({ where: { id }, include: orderInclude });
  if (!order) throw notFound();
  return orderDto(order, opts);
}

/** Cancels an order and gives its stock back. Idempotent. */
export async function cancelOrder(orderId: string, reason: string, actorId?: string) {
  const productIds = await prisma.$transaction(async (tx) => {
    const order = await tx.order.findUnique({ where: { id: orderId } });
    if (!order) throw notFound();
    if (order.status === 'CANCELLED') return [];
    if (order.status === 'DELIVERED' || order.status === 'REFUNDED') throw new AppError(409, 'order_not_cancellable');

    // Conditional update so concurrent cancellations release stock only once.
    const flipped = await tx.order.updateMany({
      where: { id: orderId, status: order.status },
      data: { status: 'CANCELLED', cancelReason: reason, expiresAt: null },
    });
    if (flipped.count === 0) return [];
    await tx.delivery.updateMany({ where: { orderId }, data: { status: 'FAILED', failedReason: reason } });
    return releaseOrderStock(tx, orderId, actorId);
  });
  void pushStockToWoo(productIds);
}

/** Releases stock of unpaid orders whose payment window is over. Runs every minute. */
export async function expireUnpaidOrders() {
  const expired = await prisma.order.findMany({
    where: { status: 'PENDING_PAYMENT', paymentStatus: { not: 'PAID' }, expiresAt: { lt: new Date() } },
    select: { id: true },
    take: 100,
  });
  for (const o of expired) {
    await cancelOrder(o.id, 'Payment not received in time').catch((e) => console.error('[orders] expire failed', o.id, e));
  }
  if (expired.length) console.log(`[orders] expired ${expired.length} unpaid order(s)`);
}
