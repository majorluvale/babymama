import { Router } from 'express';
import { Prisma, ProductCondition } from '@prisma/client';
import { z } from 'zod';
import {
  bannerDto,
  bundleDto,
  bundleInclude,
  categoryDto,
  productDto,
  productInclude,
  zoneDto,
} from '../../lib/dto';
import { notFound } from '../../lib/errors';
import { ah, pageQuery, paged, skipTake } from '../../lib/http';
import { prisma } from '../../lib/prisma';
import { optionalAuth, requireAuth } from '../../middleware/auth';

export const catalogRouter = Router();

export function bundleWindow(now = new Date()): Prisma.BundleWhereInput {
  return {
    active: true,
    AND: [{ OR: [{ startsAt: null }, { startsAt: { lte: now } }] }, { OR: [{ endsAt: null }, { endsAt: { gte: now } }] }],
  };
}

function bannerWindow(now = new Date()): Prisma.BannerWhereInput {
  return {
    active: true,
    AND: [{ OR: [{ startsAt: null }, { startsAt: { lte: now } }] }, { OR: [{ endsAt: null }, { endsAt: { gte: now } }] }],
  };
}

/** Products visible in the shop: active and in stock. */
const shopVisible: Prisma.ProductWhereInput = { status: 'ACTIVE', stock: { gt: 0 } };

async function favoriteSet(userId: string | undefined, productIds: string[]): Promise<Set<string>> {
  if (!userId || productIds.length === 0) return new Set();
  const favs = await prisma.favorite.findMany({
    where: { userId, productId: { in: productIds } },
    select: { productId: true },
  });
  return new Set(favs.map((f) => f.productId));
}

async function categoryWithChildren(ref: string): Promise<string[] | null> {
  const cat = await prisma.category.findFirst({
    where: { OR: [{ id: ref }, { slug: ref }] },
    include: { children: { select: { id: true } } },
  });
  return cat ? [cat.id, ...cat.children.map((c) => c.id)] : null;
}

const activeTiers = () =>
  prisma.discountTier.findMany({ where: { active: true }, orderBy: { minItems: 'asc' }, select: { minItems: true, percent: true } });

catalogRouter.get(
  '/categories',
  ah(async (_req, res) => {
    const cats = await prisma.category.findMany({ include: { parent: true }, orderBy: [{ position: 'asc' }, { nameEn: 'asc' }] });
    res.json(cats.map((c) => categoryDto(c)));
  }),
);

catalogRouter.get(
  '/zones',
  ah(async (_req, res) => {
    const zones = await prisma.deliveryZone.findMany({ where: { active: true }, orderBy: [{ position: 'asc' }, { name: 'asc' }] });
    res.json(zones.map(zoneDto));
  }),
);

catalogRouter.get(
  '/discount-tiers',
  ah(async (_req, res) => {
    res.json(await activeTiers());
  }),
);

catalogRouter.get(
  '/home',
  optionalAuth,
  ah(async (req, res) => {
    const now = new Date();
    const [banners, categories, newArrivals, featured, bundles, tiers] = await Promise.all([
      prisma.banner.findMany({ where: bannerWindow(now), orderBy: [{ position: 'asc' }, { createdAt: 'desc' }] }),
      prisma.category.findMany({ where: { parentId: null }, orderBy: [{ position: 'asc' }, { nameEn: 'asc' }] }),
      prisma.product.findMany({ where: shopVisible, include: productInclude, orderBy: { createdAt: 'desc' }, take: 12 }),
      prisma.product.findMany({
        where: { ...shopVisible, isFeatured: true },
        include: productInclude,
        orderBy: { updatedAt: 'desc' },
        take: 12,
      }),
      prisma.bundle.findMany({ where: bundleWindow(now), include: bundleInclude, orderBy: { createdAt: 'desc' }, take: 10 }),
      activeTiers(),
    ]);
    const favs = await favoriteSet(req.user?.id, [...newArrivals, ...featured].map((p) => p.id));
    res.json({
      banners: banners.map(bannerDto),
      categories: categories.map((c) => categoryDto(c)),
      newArrivals: newArrivals.map((p) => productDto(p, { favorite: favs.has(p.id) })),
      featured: featured.map((p) => productDto(p, { favorite: favs.has(p.id) })),
      bundles: bundles.map(bundleDto).filter((b) => b.available > 0),
      discountTiers: tiers,
    });
  }),
);

const listQuery = pageQuery.extend({
  q: z.string().trim().max(100).optional(),
  category: z.string().optional(),
  /** One size or several, comma-separated: "M,L". */
  size: z.string().optional(),
  /** Colour keys, comma-separated. */
  color: z.string().optional(),
  brand: z.string().optional(),
  condition: z.nativeEnum(ProductCondition).optional(),
  minPrice: z.coerce.number().int().min(0).optional(),
  maxPrice: z.coerce.number().int().min(0).optional(),
  featured: z.enum(['true', 'false']).optional(),
  sort: z.enum(['newest', 'price_asc', 'price_desc', 'popular']).default('newest'),
});

catalogRouter.get(
  '/products',
  optionalAuth,
  ah(async (req, res) => {
    const q = listQuery.parse(req.query);
    const and: Prisma.ProductWhereInput[] = [shopVisible];

    if (q.q) {
      and.push({
        OR: [
          { title: { contains: q.q, mode: 'insensitive' } },
          { brand: { contains: q.q, mode: 'insensitive' } },
          { category: { nameEn: { contains: q.q, mode: 'insensitive' } } },
          { category: { nameFr: { contains: q.q, mode: 'insensitive' } } },
          { description: { contains: q.q, mode: 'insensitive' } },
          { sku: { equals: q.q, mode: 'insensitive' } },
        ],
      });
    }
    if (q.category) {
      const ids = await categoryWithChildren(q.category);
      and.push({ categoryId: { in: ids ?? [] } });
    }
    const list = (v?: string) => (v ?? '').split(',').map((s) => s.trim()).filter(Boolean);
    if (q.size) and.push({ OR: list(q.size).map((size) => ({ size: { equals: size, mode: 'insensitive' as const } })) });
    if (q.color) and.push({ color: { in: list(q.color) } });
    if (q.brand) and.push({ brand: { contains: q.brand, mode: 'insensitive' } });
    if (q.condition) and.push({ condition: q.condition });
    if (q.minPrice !== undefined) and.push({ price: { gte: q.minPrice } });
    if (q.maxPrice !== undefined) and.push({ price: { lte: q.maxPrice } });
    if (q.featured === 'true') and.push({ isFeatured: true });

    const orderBy: Prisma.ProductOrderByWithRelationInput[] =
      q.sort === 'price_asc'
        ? [{ price: 'asc' }]
        : q.sort === 'price_desc'
          ? [{ price: 'desc' }]
          : q.sort === 'popular'
            ? [{ favorites: { _count: 'desc' } }, { createdAt: 'desc' }]
            : [{ createdAt: 'desc' }];

    const where: Prisma.ProductWhereInput = { AND: and };
    const [items, total] = await Promise.all([
      prisma.product.findMany({ where, include: productInclude, orderBy, ...skipTake(q.page, q.pageSize) }),
      prisma.product.count({ where }),
    ]);
    const favs = await favoriteSet(req.user?.id, items.map((p) => p.id));
    res.json(paged(items.map((p) => productDto(p, { favorite: favs.has(p.id) })), total, q.page, q.pageSize));
  }),
);

catalogRouter.get(
  '/products/:id',
  optionalAuth,
  ah(async (req, res) => {
    const p = await prisma.product.findUnique({ where: { id: req.params.id }, include: productInclude });
    const publicStatus = p?.status === 'ACTIVE' || p?.status === 'SOLD_OUT';
    const canSee = p && (publicStatus || p.sellerId === req.user?.id || req.user?.role === 'ADMIN');
    if (!p || !canSee) throw notFound();

    const [related, favs, tiers] = await Promise.all([
      prisma.product.findMany({
        where: { ...shopVisible, categoryId: p.categoryId, id: { not: p.id } },
        include: productInclude,
        orderBy: { createdAt: 'desc' },
        take: 8,
      }),
      favoriteSet(req.user?.id, [p.id]),
      activeTiers(),
    ]);
    res.json({
      ...productDto(p, { favorite: favs.has(p.id) }),
      related: related.map((r) => productDto(r)),
      discountTiers: tiers,
    });
  }),
);

catalogRouter.get(
  '/bundles',
  ah(async (_req, res) => {
    const bundles = await prisma.bundle.findMany({ where: bundleWindow(), include: bundleInclude, orderBy: { createdAt: 'desc' } });
    res.json(bundles.map(bundleDto).filter((b) => b.available > 0));
  }),
);

catalogRouter.get(
  '/bundles/:id',
  ah(async (req, res) => {
    const bundle = await prisma.bundle.findUnique({ where: { id: req.params.id }, include: bundleInclude });
    if (!bundle) throw notFound();
    res.json(bundleDto(bundle));
  }),
);

// ---- Favorites ----

catalogRouter.get(
  '/me/favorites',
  requireAuth,
  ah(async (req, res) => {
    const favs = await prisma.favorite.findMany({
      where: { userId: req.user!.id },
      include: { product: { include: productInclude } },
      orderBy: { createdAt: 'desc' },
    });
    res.json(favs.map((f) => productDto(f.product, { favorite: true })));
  }),
);

catalogRouter.post(
  '/me/favorites/:productId',
  requireAuth,
  ah(async (req, res) => {
    const userId = req.user!.id;
    const productId = req.params.productId;
    await prisma.favorite.upsert({
      where: { userId_productId: { userId, productId } },
      create: { userId, productId },
      update: {},
    });
    res.status(204).end();
  }),
);

catalogRouter.delete(
  '/me/favorites/:productId',
  requireAuth,
  ah(async (req, res) => {
    await prisma.favorite.deleteMany({ where: { userId: req.user!.id, productId: req.params.productId } });
    res.status(204).end();
  }),
);

// Babymama is the only seller: customer self-listing is intentionally not exposed.
// Products are created by staff through the admin API (products.admin.ts).
