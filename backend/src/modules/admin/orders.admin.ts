import { Router } from 'express';
import { OrderStatus, PaymentStatus, Prisma } from '@prisma/client';
import { z } from 'zod';
import { orderDto, orderInclude } from '../../lib/dto';
import { AppError, notFound } from '../../lib/errors';
import { ah, pageQuery, paged, skipTake } from '../../lib/http';
import { prisma } from '../../lib/prisma';
import { cancelOrder, getOrder } from '../orders/orders.service';

export const ordersAdminRouter = Router();

const listQuery = pageQuery.extend({
  status: z.nativeEnum(OrderStatus).optional(),
  paymentStatus: z.nativeEnum(PaymentStatus).optional(),
  q: z.string().trim().optional(),
});

ordersAdminRouter.get(
  '/orders',
  ah(async (req, res) => {
    const q = listQuery.parse(req.query);
    const where: Prisma.OrderWhereInput = {};
    if (q.status) where.status = q.status;
    if (q.paymentStatus) where.paymentStatus = q.paymentStatus;
    if (q.q) {
      const seq = Number(q.q.replace(/\D/g, ''));
      where.OR = [
        ...(seq ? [{ seq }] : []),
        { user: { name: { contains: q.q, mode: 'insensitive' } } },
        { user: { email: { contains: q.q, mode: 'insensitive' } } },
        { user: { phone: { contains: q.q } } },
      ];
    }
    const [items, total] = await Promise.all([
      prisma.order.findMany({ where, include: orderInclude, orderBy: { createdAt: 'desc' }, ...skipTake(q.page, q.pageSize) }),
      prisma.order.count({ where }),
    ]);
    res.json(paged(items.map((o) => orderDto(o, { revealCode: true })), total, q.page, q.pageSize));
  }),
);

ordersAdminRouter.get(
  '/orders/:id',
  ah(async (req, res) => {
    const order = await prisma.order.findUnique({
      where: { id: req.params.id },
      include: { ...orderInclude, payments: { orderBy: { createdAt: 'desc' } } },
    });
    if (!order) throw notFound();
    res.json({ ...orderDto(order, { revealCode: true }), payments: order.payments });
  }),
);

/** Forward-only workflow handled by the warehouse team. Cancellation has its own endpoint. */
const NEXT: Partial<Record<OrderStatus, OrderStatus[]>> = {
  PENDING_PAYMENT: ['CONFIRMED'],
  CONFIRMED: ['PREPARING', 'READY'],
  PREPARING: ['READY'],
  READY: ['PREPARING', 'OUT_FOR_DELIVERY'],
  OUT_FOR_DELIVERY: ['DELIVERED', 'READY'],
  DELIVERED: ['REFUNDED'],
  CANCELLED: ['REFUNDED'],
};

const updateSchema = z.object({
  status: z.nativeEnum(OrderStatus).optional(),
  paymentStatus: z.nativeEnum(PaymentStatus).optional(),
});

ordersAdminRouter.patch(
  '/orders/:id',
  ah(async (req, res) => {
    const body = updateSchema.parse(req.body);
    const order = await prisma.order.findUnique({ where: { id: req.params.id } });
    if (!order) throw notFound();
    if (body.status === 'CANCELLED') throw new AppError(400, 'invalid_status_transition');
    if (body.status && body.status !== order.status && !NEXT[order.status]?.includes(body.status)) {
      throw new AppError(409, 'invalid_status_transition');
    }
    await prisma.order.update({
      where: { id: order.id },
      data: {
        ...body,
        ...(body.status && body.status !== 'PENDING_PAYMENT' ? { expiresAt: null } : {}),
        ...(body.status === 'REFUNDED' ? { paymentStatus: 'REFUNDED' as const } : {}),
      },
    });
    if (body.status === 'DELIVERED') {
      await prisma.delivery.updateMany({ where: { orderId: order.id }, data: { status: 'DELIVERED', deliveredAt: new Date() } });
    }
    res.json(await getOrder(order.id, { revealCode: true }));
  }),
);

ordersAdminRouter.post(
  '/orders/:id/cancel',
  ah(async (req, res) => {
    const { reason } = z.object({ reason: z.string().trim().min(3).max(300) }).parse(req.body);
    await cancelOrder(req.params.id, reason, req.user!.id);
    res.json(await getOrder(req.params.id, { revealCode: true }));
  }),
);

ordersAdminRouter.post(
  '/orders/:id/assign',
  ah(async (req, res) => {
    const { driverId } = z.object({ driverId: z.string().nullable() }).parse(req.body);
    if (driverId) {
      const driver = await prisma.user.findFirst({ where: { id: driverId, role: 'DRIVER', isActive: true } });
      if (!driver) throw notFound();
    }
    const delivery = await prisma.delivery.findUnique({ where: { orderId: req.params.id } });
    if (!delivery) throw notFound();
    if (delivery.status === 'DELIVERED') throw new AppError(409, 'invalid_status_transition');
    await prisma.delivery.update({
      where: { id: delivery.id },
      data: driverId
        ? { driverId, status: 'ASSIGNED', assignedAt: new Date(), acceptedAt: null, failedReason: null }
        : { driverId: null, status: 'UNASSIGNED', assignedAt: null, acceptedAt: null },
    });
    res.json(await getOrder(req.params.id, { revealCode: true }));
  }),
);
