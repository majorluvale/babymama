import { Router } from 'express';
import { TicketStatus } from '@prisma/client';
import { z } from 'zod';
import { ticketDto, ticketInclude } from '../../lib/dto';
import { notFound } from '../../lib/errors';
import { ah } from '../../lib/http';
import { prisma } from '../../lib/prisma';
import { requireAuth } from '../../middleware/auth';

/** Customer side of the support inbox. */
export const supportRouter = Router();
supportRouter.use(requireAuth);

supportRouter.get(
  '/',
  ah(async (req, res) => {
    const tickets = await prisma.supportTicket.findMany({
      where: { userId: req.user!.id },
      include: ticketInclude,
      orderBy: { updatedAt: 'desc' },
    });
    res.json(tickets.map(ticketDto));
  }),
);

const createSchema = z.object({
  subject: z.string().trim().min(3).max(140),
  message: z.string().trim().min(1).max(4000),
  orderId: z.string().nullish(),
});

supportRouter.post(
  '/',
  ah(async (req, res) => {
    const body = createSchema.parse(req.body);
    const userId = req.user!.id;
    if (body.orderId) {
      const own = await prisma.order.count({ where: { id: body.orderId, userId } });
      if (!own) throw notFound();
    }
    const ticket = await prisma.supportTicket.create({
      data: {
        userId,
        orderId: body.orderId ?? null,
        subject: body.subject,
        messages: { create: { senderId: userId, body: body.message, isStaff: false } },
      },
      include: ticketInclude,
    });
    res.status(201).json(ticketDto(ticket));
  }),
);

supportRouter.get(
  '/:id',
  ah(async (req, res) => {
    const ticket = await prisma.supportTicket.findFirst({ where: { id: req.params.id, userId: req.user!.id }, include: ticketInclude });
    if (!ticket) throw notFound();
    res.json(ticketDto(ticket));
  }),
);

const messageSchema = z.object({ body: z.string().trim().min(1).max(4000) });

supportRouter.post(
  '/:id/messages',
  ah(async (req, res) => {
    const { body } = messageSchema.parse(req.body);
    const ticket = await prisma.supportTicket.findFirst({ where: { id: req.params.id, userId: req.user!.id } });
    if (!ticket) throw notFound();
    const updated = await prisma.supportTicket.update({
      where: { id: ticket.id },
      data: { status: 'OPEN', messages: { create: { senderId: req.user!.id, body, isStaff: false } } },
      include: ticketInclude,
    });
    res.status(201).json(ticketDto(updated));
  }),
);

/** Staff side (ADMIN / SUPPORT), mounted under /admin/support. */
export const supportAdminRouter = Router();

supportAdminRouter.get(
  '/',
  ah(async (req, res) => {
    const status = z.nativeEnum(TicketStatus).optional().parse(req.query.status || undefined);
    const tickets = await prisma.supportTicket.findMany({
      where: status ? { status } : {},
      include: ticketInclude,
      orderBy: { updatedAt: 'desc' },
      take: 200,
    });
    res.json(tickets.map(ticketDto));
  }),
);

supportAdminRouter.get(
  '/:id',
  ah(async (req, res) => {
    const ticket = await prisma.supportTicket.findUnique({ where: { id: req.params.id }, include: ticketInclude });
    if (!ticket) throw notFound();
    res.json(ticketDto(ticket));
  }),
);

supportAdminRouter.post(
  '/:id/messages',
  ah(async (req, res) => {
    const { body } = messageSchema.parse(req.body);
    const updated = await prisma.supportTicket.update({
      where: { id: req.params.id },
      // PENDING = waiting for the customer's answer.
      data: { status: 'PENDING', messages: { create: { senderId: req.user!.id, body, isStaff: true } } },
      include: ticketInclude,
    });
    res.status(201).json(ticketDto(updated));
  }),
);

supportAdminRouter.patch(
  '/:id',
  ah(async (req, res) => {
    const { status } = z.object({ status: z.nativeEnum(TicketStatus) }).parse(req.body);
    const updated = await prisma.supportTicket.update({ where: { id: req.params.id }, data: { status }, include: ticketInclude });
    res.json(ticketDto(updated));
  }),
);
