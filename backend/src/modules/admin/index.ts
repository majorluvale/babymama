import { Router } from 'express';
import { ah } from '../../lib/http';
import { prisma } from '../../lib/prisma';
import { requireAuth, requireRole } from '../../middleware/auth';
import { supportAdminRouter } from '../support/support.routes';
import { wooAdminRouter } from '../woocommerce/woo.routes';
import { contentAdminRouter } from './content.admin';
import { ordersAdminRouter } from './orders.admin';
import { peopleAdminRouter } from './people.admin';
import { productsAdminRouter } from './products.admin';

export const adminRouter = Router();

adminRouter.use(requireAuth);
// Support agents only see the support inbox; everything else is admin-only.
adminRouter.use('/support', requireRole('ADMIN', 'SUPPORT'), supportAdminRouter);
adminRouter.use(requireRole('ADMIN'));

adminRouter.get(
  '/stats',
  ah(async (_req, res) => {
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const weekAgo = new Date(today.getTime() - 6 * 24 * 60 * 60 * 1000);
    const paid = { paymentStatus: 'PAID' as const, status: { not: 'CANCELLED' as const } };

    const [ordersToday, revenueToday, byStatus, lowStock, openTickets, pendingListings, refunds, unassigned, week] =
      await Promise.all([
        prisma.order.count({ where: { createdAt: { gte: today } } }),
        prisma.order.aggregate({ where: { ...paid, createdAt: { gte: today } }, _sum: { total: true } }),
        prisma.order.groupBy({ by: ['status'], _count: { _all: true } }),
        prisma.product.findMany({
          where: { status: { in: ['ACTIVE', 'SOLD_OUT'] }, stock: { lte: prisma.product.fields.lowStockThreshold } },
          select: { id: true, title: true, sku: true, stock: true, lowStockThreshold: true },
          orderBy: { stock: 'asc' },
          take: 10,
        }),
        prisma.supportTicket.count({ where: { status: 'OPEN' } }),
        prisma.product.count({ where: { status: 'PENDING_REVIEW' } }),
        prisma.order.count({ where: { status: 'CANCELLED', paymentStatus: 'PAID' } }),
        prisma.delivery.count({ where: { status: { in: ['UNASSIGNED', 'FAILED'] }, order: { status: { in: ['CONFIRMED', 'PREPARING', 'READY'] } } } }),
        prisma.order.findMany({ where: { ...paid, createdAt: { gte: weekAgo } }, select: { createdAt: true, total: true } }),
      ]);

    const days = Array.from({ length: 7 }, (_, i) => {
      const d = new Date(weekAgo.getTime() + i * 24 * 60 * 60 * 1000);
      return { date: d.toISOString().slice(0, 10), revenue: 0, orders: 0 };
    });
    for (const o of week) {
      const idx = Math.floor((o.createdAt.getTime() - weekAgo.getTime()) / (24 * 60 * 60 * 1000));
      if (days[idx]) {
        days[idx].revenue += o.total;
        days[idx].orders += 1;
      }
    }

    res.json({
      ordersToday,
      revenueToday: revenueToday._sum.total ?? 0,
      ordersByStatus: Object.fromEntries(byStatus.map((s) => [s.status, s._count._all])),
      lowStock,
      openTickets,
      pendingListings,
      refundsToProcess: refunds,
      deliveriesToDispatch: unassigned,
      last7Days: days,
    });
  }),
);

adminRouter.use(productsAdminRouter);
adminRouter.use(ordersAdminRouter);
adminRouter.use(contentAdminRouter);
adminRouter.use(peopleAdminRouter);
adminRouter.use('/woocommerce', wooAdminRouter);
