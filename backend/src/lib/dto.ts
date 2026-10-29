import type { Banner, Category, DeliveryZone, Payment, Prisma, User } from '@prisma/client';
import { effectiveSizeType, sizeScales } from './sizes';

/** Shapes returned by the API. Keep in sync with packages/babymama_core/lib/src/models.dart. */

export const orderNumber = (seq: number) => `BM-${String(seq).padStart(6, '0')}`;

export function userDto(u: User) {
  return {
    id: u.id,
    name: u.name,
    email: u.email,
    phone: u.phone,
    role: u.role,
    locale: u.locale,
    avatarUrl: u.avatarUrl,
    isActive: u.isActive,
    hasPassword: Boolean(u.passwordHash),
    createdAt: u.createdAt,
  };
}

/** Pass the parent (when loaded) to get the inherited size scale and the "Women › Dresses" path. */
export function categoryDto(c: Category & { parent?: Category | null }) {
  const sizeType = effectiveSizeType(c);
  return {
    id: c.id,
    slug: c.slug,
    nameEn: c.nameEn,
    nameFr: c.nameFr,
    imageUrl: c.imageUrl,
    parentId: c.parentId,
    position: c.position,
    icon: c.icon,
    ownSizeType: c.sizeType,
    sizeType,
    sizes: sizeType ? sizeScales[sizeType] : [],
    parent: c.parent ? { id: c.parent.id, slug: c.parent.slug, nameEn: c.parent.nameEn, nameFr: c.parent.nameFr, icon: c.parent.icon } : null,
  };
}

export function zoneDto(z: DeliveryZone) {
  return { id: z.id, name: z.name, fee: z.fee, etaMinutes: z.etaMinutes, active: z.active, position: z.position };
}

export function bannerDto(b: Banner) {
  return { ...b };
}

export const productInclude = {
  images: { orderBy: { position: 'asc' } },
  category: { include: { parent: true } },
  seller: { select: { id: true, name: true } },
} satisfies Prisma.ProductInclude;

export type ProductWithRels = Prisma.ProductGetPayload<{ include: typeof productInclude }>;

export function productDto(p: ProductWithRels, opts: { favorite?: boolean } = {}) {
  return {
    id: p.id,
    sku: p.sku,
    title: p.title,
    description: p.description,
    brand: p.brand,
    size: p.size,
    color: p.color,
    condition: p.condition,
    price: p.price,
    compareAtPrice: p.compareAtPrice,
    stock: p.stock,
    lowStockThreshold: p.lowStockThreshold,
    status: p.status,
    isFeatured: p.isFeatured,
    source: p.source,
    wooId: p.wooId,
    rejectReason: p.rejectReason,
    images: p.images.map((i) => i.url),
    category: p.category ? categoryDto(p.category) : null,
    seller: p.seller,
    isFavorite: opts.favorite ?? false,
    createdAt: p.createdAt,
    updatedAt: p.updatedAt,
  };
}

export const bundleInclude = {
  items: { include: { product: { include: productInclude } } },
} satisfies Prisma.BundleInclude;

export type BundleWithRels = Prisma.BundleGetPayload<{ include: typeof bundleInclude }>;

export function bundleDto(b: BundleWithRels) {
  const originalPrice = b.items.reduce((sum, i) => sum + i.product.price * i.quantity, 0);
  const available =
    b.items.length === 0
      ? 0
      : Math.min(...b.items.map((i) => (i.product.status === 'ACTIVE' ? Math.floor(i.product.stock / i.quantity) : 0)));
  return {
    id: b.id,
    title: b.title,
    titleFr: b.titleFr,
    description: b.description,
    price: b.price,
    imageUrl: b.imageUrl ?? b.items[0]?.product.images[0]?.url ?? null,
    active: b.active,
    startsAt: b.startsAt,
    endsAt: b.endsAt,
    originalPrice,
    available,
    items: b.items.map((i) => ({ productId: i.productId, quantity: i.quantity, product: productDto(i.product) })),
  };
}

export const orderInclude = {
  items: true,
  zone: true,
  user: { select: { id: true, name: true, email: true, phone: true } },
  delivery: { include: { driver: { select: { id: true, name: true, phone: true } } } },
  review: true,
} satisfies Prisma.OrderInclude;

export type OrderWithRels = Prisma.OrderGetPayload<{ include: typeof orderInclude }>;

export function orderDto(o: OrderWithRels, opts: { revealCode?: boolean } = {}) {
  const d = o.delivery;
  return {
    id: o.id,
    number: orderNumber(o.seq),
    status: o.status,
    paymentStatus: o.paymentStatus,
    paymentMethod: o.paymentMethod,
    subtotal: o.subtotal,
    discount: o.discount,
    discountPercent: o.discountPercent,
    deliveryFee: o.deliveryFee,
    total: o.total,
    amountToCollect: o.paymentMethod === 'CASH_ON_DELIVERY' && o.paymentStatus !== 'PAID' ? o.total : 0,
    address: o.address,
    zone: { id: o.zone.id, name: o.zone.name, etaMinutes: o.zone.etaMinutes },
    notes: o.notes,
    deliveryCode: opts.revealCode ? o.deliveryCode : null,
    expiresAt: o.expiresAt,
    cancelReason: o.cancelReason,
    wooOrderId: o.wooOrderId,
    createdAt: o.createdAt,
    updatedAt: o.updatedAt,
    customer: o.user,
    items: o.items.map((i) => ({
      id: i.id,
      productId: i.productId,
      bundleId: i.bundleId,
      title: i.title,
      imageUrl: i.imageUrl,
      unitPrice: i.unitPrice,
      quantity: i.quantity,
    })),
    delivery: d
      ? {
          id: d.id,
          status: d.status,
          driver: d.driver,
          assignedAt: d.assignedAt,
          acceptedAt: d.acceptedAt,
          pickedUpAt: d.pickedUpAt,
          deliveredAt: d.deliveredAt,
          failedReason: d.failedReason,
          cashCollected: d.cashCollected,
          lastLat: d.lastLat,
          lastLng: d.lastLng,
          lastLocationAt: d.lastLocationAt,
        }
      : null,
    review: o.review
      ? {
          id: o.review.id,
          rating: o.review.rating,
          comment: o.review.comment,
          driverRating: o.review.driverRating,
          createdAt: o.review.createdAt,
        }
      : null,
  };
}

export function paymentDto(p: Payment) {
  return {
    id: p.id,
    orderId: p.orderId,
    method: p.method,
    status: p.status,
    amount: p.amount,
    phone: p.phone,
    providerRef: p.providerRef,
    receipt: p.receipt,
    message: p.message,
    redirectUrl: p.redirectUrl,
    createdAt: p.createdAt,
  };
}

export const ticketInclude = {
  user: { select: { id: true, name: true, email: true, phone: true } },
  order: { select: { id: true, seq: true } },
  messages: { orderBy: { createdAt: 'asc' }, include: { sender: { select: { name: true } } } },
} satisfies Prisma.SupportTicketInclude;

export type TicketWithRels = Prisma.SupportTicketGetPayload<{ include: typeof ticketInclude }>;

export function ticketDto(t: TicketWithRels) {
  const last = t.messages[t.messages.length - 1];
  return {
    id: t.id,
    subject: t.subject,
    status: t.status,
    orderId: t.orderId,
    orderNumber: t.order ? orderNumber(t.order.seq) : null,
    createdAt: t.createdAt,
    updatedAt: t.updatedAt,
    user: t.user,
    lastMessage: last ? { body: last.body, isStaff: last.isStaff, createdAt: last.createdAt } : null,
    messages: t.messages.map((m) => ({
      id: m.id,
      body: m.body,
      isStaff: m.isStaff,
      senderName: m.sender.name,
      createdAt: m.createdAt,
    })),
  };
}
