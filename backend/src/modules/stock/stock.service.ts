import type { Prisma, StockMovementType } from '@prisma/client';
import { AppError } from '../../lib/errors';
import { prisma } from '../../lib/prisma';

type Tx = Prisma.TransactionClient;

interface MoveContext {
  type?: StockMovementType;
  orderId?: string;
  userId?: string;
  reason?: string;
}

/**
 * Atomically removes `qty` units. Fails with 409 out_of_stock if not enough units are left,
 * so two customers can never buy the same last item.
 */
export async function takeStock(
  tx: Tx,
  productId: string,
  qty: number,
  ctx: MoveContext & { requireActive?: boolean } = {},
): Promise<number> {
  const where: Prisma.ProductWhereInput = { id: productId, stock: { gte: qty } };
  if (ctx.requireActive !== false) where.status = 'ACTIVE';

  const res = await tx.product.updateMany({ where, data: { stock: { decrement: qty } } });
  if (res.count === 0) throw new AppError(409, 'out_of_stock', { productId });

  const p = await tx.product.findUniqueOrThrow({ where: { id: productId }, select: { stock: true, status: true } });
  if (p.stock === 0 && p.status === 'ACTIVE') {
    await tx.product.update({ where: { id: productId }, data: { status: 'SOLD_OUT' } });
  }
  await tx.stockMovement.create({
    data: {
      productId,
      type: ctx.type ?? 'SALE',
      quantity: -qty,
      stockAfter: p.stock,
      orderId: ctx.orderId,
      userId: ctx.userId,
      reason: ctx.reason,
    },
  });
  return p.stock;
}

/** Adds `qty` units back (restock, return, cancelled order) and reactivates sold-out items. */
export async function putStock(tx: Tx, productId: string, qty: number, ctx: MoveContext = {}): Promise<number> {
  const p = await tx.product.update({
    where: { id: productId },
    data: { stock: { increment: qty } },
    select: { stock: true, status: true },
  });
  if (p.status === 'SOLD_OUT' && p.stock > 0) {
    await tx.product.update({ where: { id: productId }, data: { status: 'ACTIVE' } });
  }
  await tx.stockMovement.create({
    data: {
      productId,
      type: ctx.type ?? 'RESTOCK',
      quantity: qty,
      stockAfter: p.stock,
      orderId: ctx.orderId,
      userId: ctx.userId,
      reason: ctx.reason,
    },
  });
  return p.stock;
}

/** Gives back every unit an order took (bundles included). Safe to call twice. */
export async function releaseOrderStock(tx: Tx, orderId: string, userId?: string): Promise<string[]> {
  const moves = await tx.stockMovement.findMany({
    where: { orderId, type: { in: ['SALE', 'RELEASE'] } },
  });
  const net = new Map<string, number>();
  for (const m of moves) net.set(m.productId, (net.get(m.productId) ?? 0) + m.quantity);

  for (const [productId, quantity] of net) {
    if (quantity < 0) {
      await putStock(tx, productId, -quantity, { type: 'RELEASE', orderId, userId, reason: 'Order cancelled' });
    }
  }
  return [...net.keys()];
}

/** Manual stock change from the admin (restock, inventory correction, customer return). */
export async function adjustStock(
  productId: string,
  delta: number,
  type: 'RESTOCK' | 'ADJUSTMENT' | 'RETURN',
  userId: string,
  reason?: string,
): Promise<number> {
  return prisma.$transaction((tx) =>
    delta > 0
      ? putStock(tx, productId, delta, { type, userId, reason })
      : takeStock(tx, productId, -delta, { type, userId, reason, requireActive: false }),
  );
}
