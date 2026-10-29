import { Router } from 'express';
import { PaymentMethod } from '@prisma/client';
import { z } from 'zod';
import { orderDto, orderInclude } from '../../lib/dto';
import { AppError, notFound } from '../../lib/errors';
import { ah, pageQuery, paged, skipTake } from '../../lib/http';
import { prisma } from '../../lib/prisma';
import { isStaff, optionalAuth, requireAuth } from '../../middleware/auth';
import { cancelOrder, createOrder, getOrder, quoteCart } from './orders.service';

export const ordersRouter = Router();

const cartSchema = z.object({
  items: z.array(z.object({ productId: z.string(), quantity: z.number().int().min(1).max(50) })).max(100).default([]),
  bundles: z.array(z.object({ bundleId: z.string(), quantity: z.number().int().min(1).max(20) })).max(20).default([]),
});

ordersRouter.post(
  '/quote',
  optionalAuth,
  ah(async (req, res) => {
    const body = cartSchema.extend({ zoneId: z.string().nullish() }).parse(req.body);
    res.json(await quoteCart(body, body.zoneId ?? undefined));
  }),
);

const checkoutSchema = cartSchema.extend({
  zoneId: z.string(),
  paymentMethod: z.nativeEnum(PaymentMethod),
  address: z.object({
    recipientName: z.string().trim().min(2).max(80),
    phone: z.string().trim().min(9).max(20),
    street: z.string().trim().min(3).max(200),
    landmark: z.string().trim().max(200).nullish(),
    lat: z.number().nullish(),
    lng: z.number().nullish(),
  }),
  notes: z.string().trim().max(500).optional(),
  saveAddress: z.boolean().optional(),
});

ordersRouter.post(
  '/',
  requireAuth,
  ah(async (req, res) => {
    const body = checkoutSchema.parse(req.body);
    res.status(201).json(await createOrder(req.user!.id, body));
  }),
);

ordersRouter.get(
  '/',
  requireAuth,
  ah(async (req, res) => {
    const q = pageQuery.parse(req.query);
    const where = { userId: req.user!.id };
    const [items, total] = await Promise.all([
      prisma.order.findMany({ where, include: orderInclude, orderBy: { createdAt: 'desc' }, ...skipTake(q.page, q.pageSize) }),
      prisma.order.count({ where }),
    ]);
    res.json(paged(items.map((o) => orderDto(o, { revealCode: true })), total, q.page, q.pageSize));
  }),
);

async function loadOwnOrder(orderId: string, user: Express.Request['user']) {
  const order = await prisma.order.findUnique({ where: { id: orderId }, select: { id: true, userId: true, status: true } });
  if (!order || (order.userId !== user?.id && !isStaff(user?.role))) throw notFound();
  return order;
}

ordersRouter.get(
  '/:id',
  requireAuth,
  ah(async (req, res) => {
    const order = await loadOwnOrder(req.params.id, req.user);
    res.json(await getOrder(order.id, { revealCode: order.userId === req.user!.id || isStaff(req.user!.role) }));
  }),
);

ordersRouter.post(
  '/:id/cancel',
  requireAuth,
  ah(async (req, res) => {
    const order = await loadOwnOrder(req.params.id, req.user);
    if (order.status !== 'PENDING_PAYMENT' && order.status !== 'CONFIRMED') {
      throw new AppError(409, 'order_not_cancellable');
    }
    await cancelOrder(order.id, 'Cancelled by customer', req.user!.id);
    res.json(await getOrder(order.id, { revealCode: true }));
  }),
);

const reviewSchema = z.object({
  rating: z.number().int().min(1).max(5),
  comment: z.string().trim().max(1000).optional(),
  driverRating: z.number().int().min(1).max(5).optional(),
});

ordersRouter.post(
  '/:id/review',
  requireAuth,
  ah(async (req, res) => {
    const body = reviewSchema.parse(req.body);
    const order = await prisma.order.findFirst({ where: { id: req.params.id, userId: req.user!.id }, include: { review: true } });
    if (!order) throw notFound();
    if (order.status !== 'DELIVERED') throw new AppError(409, 'review_not_allowed');
    if (order.review) throw new AppError(409, 'review_exists');
    await prisma.review.create({ data: { ...body, orderId: order.id, userId: req.user!.id } });
    res.status(201).json(await getOrder(order.id, { revealCode: true }));
  }),
);
