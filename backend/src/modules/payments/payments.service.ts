import type { PaymentMethod, Prisma } from '@prisma/client';
import { orderNumber, paymentDto } from '../../lib/dto';
import { AppError, notFound } from '../../lib/errors';
import { prisma } from '../../lib/prisma';
import { pushOrderToWoo } from '../woocommerce/woo.sync';
import { getProvider, isMock } from './providers';
import type { InitiateResult, PaymentOutcome } from './providers/provider';

const json = (v: unknown) => (v === undefined ? undefined : (v as Prisma.InputJsonValue));

export async function initiatePayment(userId: string, orderId: string, input: { method?: PaymentMethod; phone?: string }) {
  const order = await prisma.order.findFirst({ where: { id: orderId, userId }, include: { user: true } });
  if (!order) throw notFound();
  if (order.status !== 'PENDING_PAYMENT' || order.paymentStatus === 'PAID') throw new AppError(409, 'order_not_payable');

  const method = input.method ?? order.paymentMethod;
  if (method === 'CASH_ON_DELIVERY') throw new AppError(400, 'payment_method_unavailable');
  const { provider, settings } = await getProvider(method);
  const phone = input.phone ?? order.user.phone ?? undefined;

  const payment = await prisma.payment.create({ data: { orderId, method, amount: order.total, phone } });
  // Give the customer time to approve the request on their phone before the order expires.
  const minExpiry = new Date(Date.now() + 5 * 60_000);
  await prisma.order.update({
    where: { id: orderId },
    data: {
      paymentStatus: 'PENDING',
      paymentMethod: method,
      expiresAt: order.expiresAt && order.expiresAt > minExpiry ? order.expiresAt : minExpiry,
    },
  });

  let result: InitiateResult;
  try {
    result = await provider.initiate({
      paymentId: payment.id,
      reference: orderNumber(order.seq),
      amount: order.total,
      phone,
      email: order.user.email,
      name: order.user.name,
    }, settings);
  } catch (e) {
    await prisma.payment.update({ where: { id: payment.id }, data: { status: 'FAILED', message: (e as Error).message } });
    await prisma.order.update({ where: { id: orderId }, data: { paymentStatus: 'FAILED' } });
    if (e instanceof AppError) throw e;
    console.error('[payments] initiate failed', e);
    throw new AppError(502, 'payment_failed');
  }

  const updated = await prisma.payment.update({
    where: { id: payment.id },
    data: {
      providerRef: result.providerRef,
      redirectUrl: result.redirectUrl,
      message: result.message,
      raw: json(result.raw),
      status: result.status === 'FAILED' ? 'FAILED' : 'PENDING',
    },
  });

  if (result.status === 'FAILED') {
    await prisma.order.update({ where: { id: orderId }, data: { paymentStatus: 'FAILED' } });
  } else if (result.status === 'SUCCESS') {
    await settlePayment({ paymentId: payment.id }, { success: true, raw: result.raw });
  } else if (isMock(provider)) {
    setTimeout(() => {
      settlePayment({ paymentId: payment.id }, { success: true, receipt: `SIM${Date.now().toString(36).toUpperCase()}` }).catch(
        (e) => console.error('[payments] mock settle failed', e),
      );
    }, 4000);
  }
  return paymentDto(updated);
}

/**
 * Applies a provider result. Idempotent: callbacks may arrive several times.
 * A payment received after the order expired is kept as PAID + CANCELLED so an admin refunds it.
 */
export async function settlePayment(where: { paymentId?: string; providerRef?: string }, outcome: PaymentOutcome) {
  const payment = await prisma.payment.findFirst({
    where: where.paymentId ? { id: where.paymentId } : { providerRef: where.providerRef },
    include: { order: true },
  });
  if (!payment) {
    console.warn('[payments] unknown payment', where);
    return null;
  }
  if (payment.status !== 'PENDING') return payment;

  let result = outcome;
  if (result.success && result.amount !== undefined && result.amount < payment.amount) {
    result = { ...result, success: false, message: `Amount mismatch: received ${result.amount}, expected ${payment.amount}` };
  }

  if (!result.success) {
    await prisma.payment.update({
      where: { id: payment.id },
      data: { status: 'FAILED', message: result.message, raw: json(result.raw) },
    });
    if (payment.order.paymentStatus !== 'PAID') {
      await prisma.order.update({ where: { id: payment.orderId }, data: { paymentStatus: 'FAILED' } });
    }
    return payment;
  }

  const order = payment.order;
  await prisma.$transaction([
    prisma.payment.update({
      where: { id: payment.id },
      data: { status: 'SUCCESS', receipt: result.receipt, message: result.message, raw: json(result.raw) },
    }),
    prisma.order.update({
      where: { id: order.id },
      data:
        order.status === 'CANCELLED'
          ? { paymentStatus: 'PAID', cancelReason: `${order.cancelReason ?? 'Cancelled'} - paid after cancellation, refund required` }
          : { paymentStatus: 'PAID', status: order.status === 'PENDING_PAYMENT' ? 'CONFIRMED' : order.status, expiresAt: null },
    }),
  ]);
  if (order.status !== 'CANCELLED') void pushOrderToWoo(order.id);
  return payment;
}

export async function getPaymentForUser(paymentId: string, user: { id: string; role: string }) {
  const payment = await prisma.payment.findUnique({ where: { id: paymentId }, include: { order: { select: { userId: true } } } });
  if (!payment || (payment.order.userId !== user.id && user.role !== 'ADMIN')) throw notFound();
  // Serverless functions stop after responding, so the timer that settles simulated payments may never fire:
  // settle them here, when the app polls.
  if (payment.status === 'PENDING' && payment.providerRef?.startsWith('MOCK-') && Date.now() - payment.createdAt.getTime() > 4000) {
    await settlePayment({ paymentId: payment.id }, { success: true, receipt: `SIM${Date.now().toString(36).toUpperCase()}` });
    const settled = await prisma.payment.findUniqueOrThrow({ where: { id: payment.id } });
    return paymentDto(settled);
  }
  return paymentDto(payment);
}
