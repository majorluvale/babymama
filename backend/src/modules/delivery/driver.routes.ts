import { Router } from 'express';
import { Prisma, VehicleType } from '@prisma/client';
import { z } from 'zod';
import { orderDto, orderInclude } from '../../lib/dto';
import { AppError, notFound } from '../../lib/errors';
import { ah } from '../../lib/http';
import { prisma } from '../../lib/prisma';
import { requireAuth, requireRole } from '../../middleware/auth';

/** Endpoints used by the rider (livreur) app. */
export const driverRouter = Router();
driverRouter.use(requireAuth, requireRole('DRIVER'));

const deliveryInclude = { order: { include: orderInclude } } satisfies Prisma.DeliveryInclude;
type DeliveryWithOrder = Prisma.DeliveryGetPayload<{ include: typeof deliveryInclude }>;

const deliveryDto = (d: DeliveryWithOrder) => ({
  id: d.id,
  status: d.status,
  assignedAt: d.assignedAt,
  acceptedAt: d.acceptedAt,
  pickedUpAt: d.pickedUpAt,
  deliveredAt: d.deliveredAt,
  failedReason: d.failedReason,
  cashCollected: d.cashCollected,
  order: orderDto(d.order),
});

const ACTIVE: Prisma.DeliveryWhereInput['status'] = { in: ['ASSIGNED', 'ACCEPTED', 'PICKED_UP', 'IN_TRANSIT'] };
const DISPATCHABLE_ORDER: Prisma.OrderWhereInput = { status: { in: ['CONFIRMED', 'PREPARING', 'READY'] } };

const startOfToday = () => {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  return d;
};

driverRouter.get(
  '/me',
  ah(async (req, res) => {
    const userId = req.user!.id;
    const profile = await prisma.driverProfile.upsert({
      where: { userId },
      create: { userId },
      update: {},
      include: { zone: true },
    });
    const todayFilter = { driverId: userId, status: 'DELIVERED' as const, deliveredAt: { gte: startOfToday() } };
    const [deliveredToday, cash, active] = await Promise.all([
      prisma.delivery.count({ where: todayFilter }),
      prisma.delivery.aggregate({ where: todayFilter, _sum: { cashCollected: true } }),
      prisma.delivery.count({ where: { driverId: userId, status: ACTIVE } }),
    ]);
    res.json({
      ...profile,
      user: req.user,
      stats: { deliveredToday, activeDeliveries: active, cashCollectedToday: cash._sum.cashCollected ?? 0 },
    });
  }),
);

const profileSchema = z.object({
  isOnline: z.boolean().optional(),
  vehicleType: z.nativeEnum(VehicleType).optional(),
  plateNumber: z.string().trim().max(20).nullish(),
  zoneId: z.string().nullish(),
});

driverRouter.patch(
  '/me',
  ah(async (req, res) => {
    const data = profileSchema.parse(req.body);
    const profile = await prisma.driverProfile.upsert({
      where: { userId: req.user!.id },
      create: { userId: req.user!.id, ...data },
      update: { ...data, lastSeenAt: new Date() },
    });
    res.json(profile);
  }),
);

const locationSchema = z.object({ lat: z.number().min(-90).max(90), lng: z.number().min(-180).max(180) });

driverRouter.post(
  '/location',
  ah(async (req, res) => {
    const { lat, lng } = locationSchema.parse(req.body);
    const userId = req.user!.id;
    const now = new Date();
    await prisma.$transaction([
      prisma.driverProfile.upsert({
        where: { userId },
        create: { userId, lastLat: lat, lastLng: lng, lastSeenAt: now },
        update: { lastLat: lat, lastLng: lng, lastSeenAt: now },
      }),
      prisma.delivery.updateMany({
        where: { driverId: userId, status: { in: ['PICKED_UP', 'IN_TRANSIT'] } },
        data: { lastLat: lat, lastLng: lng, lastLocationAt: now },
      }),
    ]);
    res.status(204).end();
  }),
);

driverRouter.get(
  '/deliveries',
  ah(async (req, res) => {
    const scope = z.enum(['available', 'active', 'history']).default('active').parse(req.query.scope);
    const userId = req.user!.id;
    const where: Prisma.DeliveryWhereInput =
      scope === 'available'
        ? { status: 'UNASSIGNED', driverId: null, order: DISPATCHABLE_ORDER }
        : scope === 'active'
          ? { driverId: userId, status: ACTIVE }
          : { driverId: userId, status: { in: ['DELIVERED', 'FAILED'] } };
    const deliveries = await prisma.delivery.findMany({
      where,
      include: deliveryInclude,
      orderBy: scope === 'history' ? { updatedAt: 'desc' } : { createdAt: 'asc' },
      take: 50,
    });
    res.json(deliveries.map(deliveryDto));
  }),
);

async function ownDelivery(id: string, driverId: string) {
  const d = await prisma.delivery.findFirst({ where: { id, driverId }, include: deliveryInclude });
  if (!d) throw notFound();
  return d;
}

driverRouter.get(
  '/deliveries/:id',
  ah(async (req, res) => {
    const d = await prisma.delivery.findUnique({ where: { id: req.params.id }, include: deliveryInclude });
    if (!d || (d.driverId !== req.user!.id && d.status !== 'UNASSIGNED')) throw notFound();
    res.json(deliveryDto(d));
  }),
);

driverRouter.post(
  '/deliveries/:id/accept',
  ah(async (req, res) => {
    const userId = req.user!.id;
    const now = new Date();
    const updated = await prisma.delivery.updateMany({
      where: {
        id: req.params.id,
        OR: [
          { driverId: null, status: 'UNASSIGNED' },
          { driverId: userId, status: 'ASSIGNED' },
        ],
        order: DISPATCHABLE_ORDER,
      },
      data: { driverId: userId, status: 'ACCEPTED', acceptedAt: now },
    });
    if (updated.count === 0) throw new AppError(409, 'delivery_not_available');
    await prisma.delivery.updateMany({ where: { id: req.params.id, assignedAt: null }, data: { assignedAt: now } });
    res.json(deliveryDto(await ownDelivery(req.params.id, userId)));
  }),
);

const statusSchema = z.object({ status: z.enum(['PICKED_UP', 'IN_TRANSIT']) });

driverRouter.post(
  '/deliveries/:id/status',
  ah(async (req, res) => {
    const { status } = statusSchema.parse(req.body);
    const d = await ownDelivery(req.params.id, req.user!.id);
    const allowedFrom = status === 'PICKED_UP' ? ['ACCEPTED'] : ['ACCEPTED', 'PICKED_UP'];
    if (!allowedFrom.includes(d.status)) throw new AppError(409, 'invalid_status_transition');
    const now = new Date();
    await prisma.$transaction([
      prisma.delivery.update({
        where: { id: d.id },
        data: { status, pickedUpAt: d.pickedUpAt ?? now },
      }),
      prisma.order.update({ where: { id: d.orderId }, data: { status: 'OUT_FOR_DELIVERY' } }),
    ]);
    res.json(deliveryDto(await ownDelivery(d.id, req.user!.id)));
  }),
);

// Basic brute-force protection for the 4-digit delivery code.
const failedCodes = new Map<string, { count: number; until: number }>();

const completeSchema = z.object({
  code: z.string().trim().regex(/^\d{4}$/),
  cashCollected: z.number().int().min(0).optional(),
});

driverRouter.post(
  '/deliveries/:id/complete',
  ah(async (req, res) => {
    const body = completeSchema.parse(req.body);
    const d = await ownDelivery(req.params.id, req.user!.id);
    if (!['ACCEPTED', 'PICKED_UP', 'IN_TRANSIT'].includes(d.status)) throw new AppError(409, 'delivery_not_available');

    const attempts = failedCodes.get(d.id);
    if (attempts && attempts.count >= 5 && attempts.until > Date.now()) throw new AppError(429, 'invalid_delivery_code');
    if (body.code !== d.order.deliveryCode) {
      const count = (attempts && attempts.until > Date.now() ? attempts.count : 0) + 1;
      failedCodes.set(d.id, { count, until: Date.now() + 15 * 60_000 });
      throw new AppError(400, 'invalid_delivery_code');
    }
    failedCodes.delete(d.id);

    const collectCash = d.order.paymentMethod === 'CASH_ON_DELIVERY' && d.order.paymentStatus !== 'PAID';
    const now = new Date();
    await prisma.$transaction([
      prisma.delivery.update({
        where: { id: d.id },
        data: {
          status: 'DELIVERED',
          deliveredAt: now,
          pickedUpAt: d.pickedUpAt ?? now,
          cashCollected: collectCash ? (body.cashCollected ?? d.order.total) : null,
        },
      }),
      prisma.order.update({
        where: { id: d.orderId },
        data: { status: 'DELIVERED', ...(collectCash ? { paymentStatus: 'PAID' as const } : {}) },
      }),
    ]);
    res.json(deliveryDto(await ownDelivery(d.id, req.user!.id)));
  }),
);

const failSchema = z.object({ reason: z.string().trim().min(3).max(300) });

driverRouter.post(
  '/deliveries/:id/fail',
  ah(async (req, res) => {
    const { reason } = failSchema.parse(req.body);
    const d = await ownDelivery(req.params.id, req.user!.id);
    if (!['ACCEPTED', 'PICKED_UP', 'IN_TRANSIT'].includes(d.status)) throw new AppError(409, 'delivery_not_available');
    await prisma.$transaction([
      prisma.delivery.update({ where: { id: d.id }, data: { status: 'FAILED', failedReason: reason } }),
      // Back to the warehouse queue: an admin reschedules or reassigns it.
      prisma.order.update({ where: { id: d.orderId }, data: { status: 'READY' } }),
    ]);
    res.json(deliveryDto(await ownDelivery(d.id, req.user!.id)));
  }),
);
