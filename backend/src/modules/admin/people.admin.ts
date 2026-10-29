import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { Prisma, Role, VehicleType } from '@prisma/client';
import { z } from 'zod';
import { orderNumber, userDto } from '../../lib/dto';
import { AppError } from '../../lib/errors';
import { ah, pageQuery, paged, skipTake } from '../../lib/http';
import { prisma } from '../../lib/prisma';

/** Customers, staff, riders and reviews. */
export const peopleAdminRouter = Router();

peopleAdminRouter.get(
  '/users',
  ah(async (req, res) => {
    const q = pageQuery.extend({ role: z.nativeEnum(Role).optional(), q: z.string().trim().optional() }).parse(req.query);
    const where: Prisma.UserWhereInput = {};
    if (q.role) where.role = q.role;
    if (q.q) {
      where.OR = [
        { name: { contains: q.q, mode: 'insensitive' } },
        { email: { contains: q.q, mode: 'insensitive' } },
        { phone: { contains: q.q } },
      ];
    }
    const [users, total] = await Promise.all([
      prisma.user.findMany({
        where,
        include: { _count: { select: { orders: true } } },
        orderBy: { createdAt: 'desc' },
        ...skipTake(q.page, q.pageSize),
      }),
      prisma.user.count({ where }),
    ]);
    res.json(paged(users.map((u) => ({ ...userDto(u), orderCount: u._count.orders })), total, q.page, q.pageSize));
  }),
);

peopleAdminRouter.patch(
  '/users/:id',
  ah(async (req, res) => {
    const data = z.object({ role: z.nativeEnum(Role).optional(), isActive: z.boolean().optional() }).parse(req.body);
    if (req.params.id === req.user!.id && (data.role !== undefined || data.isActive === false)) {
      throw new AppError(400, 'forbidden');
    }
    const user = await prisma.user.update({ where: { id: req.params.id }, data });
    res.json(userDto(user));
  }),
);

/** Staff accounts (admin / support / rider) are created here; customers sign up themselves. */
const staffSchema = z.object({
  name: z.string().trim().min(2).max(80),
  email: z.string().trim().toLowerCase().email(),
  phone: z.string().trim().max(20).optional(),
  password: z.string().min(8).max(100),
  role: z.enum(['ADMIN', 'SUPPORT', 'DRIVER']).default('DRIVER'),
  vehicleType: z.nativeEnum(VehicleType).default('MOTORBIKE'),
  plateNumber: z.string().trim().max(20).optional(),
});

peopleAdminRouter.post(
  '/staff',
  ah(async (req, res) => {
    const body = staffSchema.parse(req.body);
    if (await prisma.user.findUnique({ where: { email: body.email } })) throw new AppError(409, 'email_taken');
    const user = await prisma.user.create({
      data: {
        name: body.name,
        email: body.email,
        phone: body.phone,
        role: body.role,
        passwordHash: await bcrypt.hash(body.password, 10),
        driverProfile:
          body.role === 'DRIVER' ? { create: { vehicleType: body.vehicleType, plateNumber: body.plateNumber } } : undefined,
      },
    });
    res.status(201).json(userDto(user));
  }),
);

peopleAdminRouter.get(
  '/drivers',
  ah(async (_req, res) => {
    const drivers = await prisma.user.findMany({
      where: { role: 'DRIVER' },
      include: {
        driverProfile: { include: { zone: true } },
        deliveries: { where: { status: { in: ['ASSIGNED', 'ACCEPTED', 'PICKED_UP', 'IN_TRANSIT'] } }, select: { id: true } },
      },
      orderBy: { name: 'asc' },
    });
    const ratings = await prisma.review.groupBy({
      by: ['orderId'],
      _avg: { driverRating: true },
      where: { driverRating: { not: null } },
    });
    const ratingByOrder = new Map(ratings.map((r) => [r.orderId, r._avg.driverRating ?? 0]));
    const delivered = await prisma.delivery.findMany({
      where: { status: 'DELIVERED', driverId: { in: drivers.map((d) => d.id) } },
      select: { driverId: true, orderId: true },
    });
    res.json(
      drivers.map((d) => {
        const mine = delivered.filter((x) => x.driverId === d.id);
        const rated = mine.map((x) => ratingByOrder.get(x.orderId)).filter((r): r is number => typeof r === 'number' && r > 0);
        return {
          ...userDto(d),
          profile: d.driverProfile,
          activeDeliveries: d.deliveries.length,
          deliveredCount: mine.length,
          rating: rated.length ? Math.round((rated.reduce((s, r) => s + r, 0) / rated.length) * 10) / 10 : null,
        };
      }),
    );
  }),
);

peopleAdminRouter.get(
  '/reviews',
  ah(async (req, res) => {
    const q = pageQuery.parse(req.query);
    const [items, total, avg] = await Promise.all([
      prisma.review.findMany({
        include: { user: { select: { name: true } }, order: { select: { seq: true, id: true } } },
        orderBy: { createdAt: 'desc' },
        ...skipTake(q.page, q.pageSize),
      }),
      prisma.review.count(),
      prisma.review.aggregate({ _avg: { rating: true, driverRating: true } }),
    ]);
    res.json({
      ...paged(
        items.map((r) => ({
          id: r.id,
          rating: r.rating,
          driverRating: r.driverRating,
          comment: r.comment,
          createdAt: r.createdAt,
          customerName: r.user.name,
          orderId: r.order.id,
          orderNumber: orderNumber(r.order.seq),
        })),
        total,
        q.page,
        q.pageSize,
      ),
      averageRating: avg._avg.rating,
      averageDriverRating: avg._avg.driverRating,
    });
  }),
);
