import type { ProductCondition, ProductStatus } from '@prisma/client';
import { config } from '../../config';
import { orderNumber } from '../../lib/dto';
import { prisma } from '../../lib/prisma';
import { wooEnabled, wooFetch, type WooProduct } from './woo.client';

/**
 * Two-way WooCommerce sync:
 *  - products created/edited in WooCommerce arrive through the webhook (or a full import);
 *  - stock changes made by Babymama (sales, cancellations, admin adjustments) are pushed back;
 *  - optionally, products created in the Babymama admin and paid orders are copied to WooCommerce.
 * Stock pushed to Woo comes back as a webhook with the same quantity, which is a no-op, so there is no loop.
 */

const stripHtml = (html: string) =>
  html
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/p>/gi, '\n')
    .replace(/<[^>]+>/g, '')
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&#8217;|&rsquo;/g, "'")
    .replace(/\n{3,}/g, '\n\n')
    .trim();

const attr = (p: WooProduct, pattern: RegExp) => p.attributes.find((a) => pattern.test(a.name))?.options[0] ?? null;

function mapCondition(value: string | null): ProductCondition {
  const v = (value ?? '').toLowerCase();
  if (/tag|étiquette|etiquette/.test(v)) return 'NEW_WITH_TAGS';
  if (/new|neuf/.test(v)) return 'NEW_WITHOUT_TAGS';
  if (/very|très|tres/.test(v)) return 'VERY_GOOD';
  if (/satisf|fair|correct/.test(v)) return 'SATISFACTORY';
  return 'GOOD';
}

async function categoryFor(p: WooProduct): Promise<string | null> {
  const wc = p.categories.find((c) => c.slug !== 'uncategorized');
  if (!wc) return null;
  const existing = await prisma.category.findFirst({ where: { OR: [{ wooId: wc.id }, { slug: wc.slug }] } });
  if (existing) {
    if (existing.wooId !== wc.id) await prisma.category.update({ where: { id: existing.id }, data: { wooId: wc.id } });
    return existing.id;
  }
  const created = await prisma.category.create({ data: { slug: wc.slug, nameEn: wc.name, nameFr: wc.name, wooId: wc.id } });
  return created.id;
}

/** Creates or updates the local copy of a WooCommerce product. Returns 'created' | 'updated'. */
export async function upsertFromWoo(wp: WooProduct): Promise<'created' | 'updated'> {
  const regular = Math.round(parseFloat(wp.regular_price || wp.price || '0'));
  const price = Math.round(parseFloat(wp.price || wp.regular_price || '0'));
  const stock = wp.manage_stock ? Math.max(0, wp.stock_quantity ?? 0) : wp.stock_status === 'instock' ? 1 : 0;
  const status: ProductStatus = wp.status !== 'publish' ? 'DRAFT' : stock > 0 ? 'ACTIVE' : 'SOLD_OUT';
  const categoryId = await categoryFor(wp);

  const fields = {
    title: wp.name,
    description: stripHtml(wp.description || wp.short_description || ''),
    price,
    compareAtPrice: regular > price ? regular : null,
    brand: attr(wp, /brand|marque/i),
    size: attr(wp, /size|taille/i),
    color: attr(wp, /colou?r|couleur/i),
    condition: mapCondition(attr(wp, /condition|état|etat/i)),
    categoryId,
    status,
  };
  const images = wp.images.map((img, position) => ({ url: img.src, position }));

  const existing = await prisma.product.findUnique({ where: { wooId: wp.id } });
  if (existing) {
    const skuFree = wp.sku && wp.sku !== existing.sku && !(await prisma.product.findUnique({ where: { sku: wp.sku } }));
    const delta = stock - existing.stock;
    await prisma.$transaction(async (tx) => {
      await tx.product.update({
        where: { id: existing.id },
        data: {
          ...fields,
          ...(skuFree ? { sku: wp.sku } : {}),
          // Keep archived products archived.
          status: existing.status === 'ARCHIVED' ? 'ARCHIVED' : status,
          stock,
          images: { deleteMany: {}, create: images },
        },
      });
      if (delta !== 0) {
        await tx.stockMovement.create({
          data: { productId: existing.id, type: 'WOO_SYNC', quantity: delta, stockAfter: stock, reason: 'WooCommerce update' },
        });
      }
    });
    return 'updated';
  }

  const skuTaken = wp.sku ? await prisma.product.findUnique({ where: { sku: wp.sku } }) : null;
  await prisma.product.create({
    data: {
      ...fields,
      sku: wp.sku && !skuTaken ? wp.sku : `WOO-${wp.id}`,
      wooId: wp.id,
      source: 'WOOCOMMERCE',
      stock,
      images: { create: images },
      movements: stock > 0 ? { create: { type: 'WOO_SYNC', quantity: stock, stockAfter: stock, reason: 'Imported from WooCommerce' } } : undefined,
    },
  });
  return 'created';
}

export async function archiveFromWoo(wooId: number) {
  await prisma.product.updateMany({ where: { wooId }, data: { status: 'ARCHIVED' } });
}

export async function importAllFromWoo() {
  const result = { created: 0, updated: 0, errors: [] as string[] };
  for (let page = 1; page < 200; page++) {
    const batch = await wooFetch<WooProduct[]>('/products', { query: { per_page: 50, page } });
    for (const wp of batch) {
      try {
        result[await upsertFromWoo(wp)]++;
      } catch (e) {
        result.errors.push(`#${wp.id} ${wp.name}: ${(e as Error).message}`);
      }
    }
    if (batch.length < 50) break;
  }
  return result;
}

/** Fire-and-forget: never fails the caller. */
export async function pushStockToWoo(productIds: string[]) {
  if (!wooEnabled() || !config.woo.pushStock || productIds.length === 0) return;
  try {
    const products = await prisma.product.findMany({
      where: { id: { in: productIds }, wooId: { not: null } },
      select: { wooId: true, stock: true },
    });
    for (const p of products) {
      await wooFetch(`/products/${p.wooId}`, { method: 'PUT', body: { manage_stock: true, stock_quantity: p.stock } }).catch((e) =>
        console.error('[woo] stock push failed', p.wooId, (e as Error).message),
      );
    }
  } catch (e) {
    console.error('[woo] stock push failed', e);
  }
}

export async function pushProductToWoo(productId: string) {
  if (!wooEnabled() || !config.woo.pushProducts) return;
  try {
    const p = await prisma.product.findUnique({ where: { id: productId }, include: { images: true, category: true } });
    if (!p || p.wooId) return;
    const created = await wooFetch<{ id: number }>('/products', {
      method: 'POST',
      body: {
        name: p.title,
        type: 'simple',
        status: p.status === 'ACTIVE' ? 'publish' : 'draft',
        sku: p.sku,
        regular_price: String(p.compareAtPrice ?? p.price),
        sale_price: p.compareAtPrice ? String(p.price) : '',
        description: p.description,
        manage_stock: true,
        stock_quantity: p.stock,
        images: p.images.map((i) => ({ src: i.url })),
        categories: p.category?.wooId ? [{ id: p.category.wooId }] : [],
        attributes: [
          p.size && { name: 'Size', options: [p.size], visible: true },
          p.brand && { name: 'Brand', options: [p.brand], visible: true },
        ].filter(Boolean),
      },
    });
    await prisma.product.update({ where: { id: p.id }, data: { wooId: created.id } });
  } catch (e) {
    console.error('[woo] product push failed', productId, e);
  }
}

export async function pushOrderToWoo(orderId: string) {
  if (!wooEnabled() || !config.woo.pushOrders) return;
  try {
    const order = await prisma.order.findUnique({
      where: { id: orderId },
      include: { user: true, items: { include: { product: true, bundle: { include: { items: { include: { product: true } } } } } } },
    });
    if (!order || order.wooOrderId) return;
    const lineItems: { product_id: number; quantity: number }[] = [];
    for (const item of order.items) {
      if (item.product?.wooId) lineItems.push({ product_id: item.product.wooId, quantity: item.quantity });
      for (const bi of item.bundle?.items ?? []) {
        if (bi.product.wooId) lineItems.push({ product_id: bi.product.wooId, quantity: bi.quantity * item.quantity });
      }
    }
    const address = order.address as Record<string, string | undefined>;
    const [firstName, ...rest] = order.user.name.split(' ');
    const created = await wooFetch<{ id: number }>('/orders', {
      method: 'POST',
      body: {
        status: 'processing',
        set_paid: order.paymentStatus === 'PAID',
        payment_method: order.paymentMethod.toLowerCase(),
        payment_method_title: order.paymentMethod,
        billing: { first_name: firstName, last_name: rest.join(' '), email: order.user.email, phone: address.phone ?? '' },
        shipping: { first_name: address.recipientName ?? firstName, address_1: address.street ?? '', city: 'Nairobi', country: 'KE' },
        line_items: lineItems,
        shipping_lines: [{ method_id: 'flat_rate', method_title: `Delivery ${address.zone ?? ''}`, total: String(order.deliveryFee) }],
        meta_data: [{ key: 'babymama_order', value: orderNumber(order.seq) }],
      },
    });
    await prisma.order.update({ where: { id: order.id }, data: { wooOrderId: created.id } });
  } catch (e) {
    console.error('[woo] order push failed', orderId, e);
  }
}
