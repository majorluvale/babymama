import { Router } from 'express';
import { BannerType, SizeType } from '@prisma/client';
import { z } from 'zod';
import { bannerDto, bundleDto, bundleInclude, categoryDto, zoneDto } from '../../lib/dto';
import { AppError, notFound } from '../../lib/errors';
import { ah } from '../../lib/http';
import { prisma } from '../../lib/prisma';

/** Carousel banners, bundle sales, multi-buy discounts and delivery zones. */
export const contentAdminRouter = Router();

const optionalDate = z.coerce.date().nullish();

// ---- Banners (home carousel) ----

const bannerSchema = z.object({
  titleEn: z.string().trim().min(1).max(120),
  titleFr: z.string().trim().min(1).max(120),
  subtitleEn: z.string().trim().max(200).nullish(),
  subtitleFr: z.string().trim().max(200).nullish(),
  imageUrl: z.string().url(),
  type: z.nativeEnum(BannerType).default('PROMO'),
  targetId: z.string().nullish(),
  url: z.string().url().nullish(),
  position: z.number().int().default(0),
  active: z.boolean().default(true),
  startsAt: optionalDate,
  endsAt: optionalDate,
});

contentAdminRouter.get(
  '/banners',
  ah(async (_req, res) => {
    const banners = await prisma.banner.findMany({ orderBy: [{ position: 'asc' }, { createdAt: 'desc' }] });
    res.json(banners.map(bannerDto));
  }),
);

contentAdminRouter.post(
  '/banners',
  ah(async (req, res) => {
    const banner = await prisma.banner.create({ data: bannerSchema.parse(req.body) });
    res.status(201).json(bannerDto(banner));
  }),
);

contentAdminRouter.patch(
  '/banners/:id',
  ah(async (req, res) => {
    const banner = await prisma.banner.update({ where: { id: req.params.id }, data: bannerSchema.partial().parse(req.body) });
    res.json(bannerDto(banner));
  }),
);

contentAdminRouter.delete(
  '/banners/:id',
  ah(async (req, res) => {
    await prisma.banner.delete({ where: { id: req.params.id } });
    res.status(204).end();
  }),
);

// ---- Bundles (ventes groupées / lots) ----

const bundleSchema = z.object({
  title: z.string().trim().min(2).max(140),
  titleFr: z.string().trim().max(140).nullish(),
  description: z.string().max(3000).default(''),
  price: z.number().int().min(0),
  imageUrl: z.string().url().nullish(),
  active: z.boolean().default(true),
  startsAt: optionalDate,
  endsAt: optionalDate,
  items: z
    .array(z.object({ productId: z.string(), quantity: z.number().int().min(1).max(20).default(1) }))
    .min(2)
    .max(30),
});

contentAdminRouter.get(
  '/bundles',
  ah(async (_req, res) => {
    const bundles = await prisma.bundle.findMany({ include: bundleInclude, orderBy: { createdAt: 'desc' } });
    res.json(bundles.map(bundleDto));
  }),
);

/** A bundle must be cheaper than buying its items one by one. */
async function assertBundlePrice(price: number, items: { productId: string; quantity: number }[]) {
  const products = await prisma.product.findMany({
    where: { id: { in: items.map((i) => i.productId) } },
    select: { id: true, price: true },
  });
  if (products.length !== new Set(items.map((i) => i.productId)).size) throw new AppError(400, 'product_unavailable');
  const priceOf = new Map(products.map((p) => [p.id, p.price]));
  const value = items.reduce((sum, i) => sum + (priceOf.get(i.productId) ?? 0) * i.quantity, 0);
  if (price >= value) throw new AppError(400, 'bundle_price_too_high', { itemsValue: value });
}

contentAdminRouter.post(
  '/bundles',
  ah(async (req, res) => {
    const { items, ...data } = bundleSchema.parse(req.body);
    await assertBundlePrice(data.price, items);
    const bundle = await prisma.bundle.create({
      data: { ...data, items: { create: items } },
      include: bundleInclude,
    });
    res.status(201).json(bundleDto(bundle));
  }),
);

contentAdminRouter.patch(
  '/bundles/:id',
  ah(async (req, res) => {
    const { items, ...data } = bundleSchema.partial().parse(req.body);
    if (data.price !== undefined || items) {
      const current = await prisma.bundle.findUnique({ where: { id: req.params.id }, include: { items: true } });
      if (!current) throw notFound();
      await assertBundlePrice(data.price ?? current.price, items ?? current.items);
    }
    const bundle = await prisma.bundle.update({
      where: { id: req.params.id },
      data: { ...data, ...(items ? { items: { deleteMany: {}, create: items } } : {}) },
      include: bundleInclude,
    });
    res.json(bundleDto(bundle));
  }),
);

contentAdminRouter.delete(
  '/bundles/:id',
  ah(async (req, res) => {
    // Bundles referenced by past orders are deactivated instead of deleted.
    const used = await prisma.orderItem.count({ where: { bundleId: req.params.id } });
    if (used) await prisma.bundle.update({ where: { id: req.params.id }, data: { active: false } });
    else await prisma.bundle.delete({ where: { id: req.params.id } });
    res.status(204).end();
  }),
);

// ---- Multi-buy discount tiers ----

contentAdminRouter.get(
  '/discount-tiers',
  ah(async (_req, res) => {
    res.json(await prisma.discountTier.findMany({ orderBy: { minItems: 'asc' } }));
  }),
);

const tiersSchema = z.array(
  z.object({ minItems: z.number().int().min(2).max(100), percent: z.number().int().min(1).max(90), active: z.boolean().default(true) }),
);

/** Replaces the whole tier table. */
contentAdminRouter.put(
  '/discount-tiers',
  ah(async (req, res) => {
    const tiers = tiersSchema.parse(req.body);
    await prisma.$transaction([prisma.discountTier.deleteMany({}), prisma.discountTier.createMany({ data: tiers })]);
    res.json(await prisma.discountTier.findMany({ orderBy: { minItems: 'asc' } }));
  }),
);

// ---- Delivery zones ----

const zoneSchema = z.object({
  name: z.string().trim().min(2).max(80),
  fee: z.number().int().min(0),
  etaMinutes: z.number().int().min(10).max(24 * 60).default(90),
  active: z.boolean().default(true),
  position: z.number().int().default(0),
});

contentAdminRouter.get(
  '/zones',
  ah(async (_req, res) => {
    const zones = await prisma.deliveryZone.findMany({ orderBy: [{ position: 'asc' }, { name: 'asc' }] });
    res.json(zones.map(zoneDto));
  }),
);

contentAdminRouter.post(
  '/zones',
  ah(async (req, res) => {
    res.status(201).json(zoneDto(await prisma.deliveryZone.create({ data: zoneSchema.parse(req.body) })));
  }),
);

contentAdminRouter.patch(
  '/zones/:id',
  ah(async (req, res) => {
    const zone = await prisma.deliveryZone.update({ where: { id: req.params.id }, data: zoneSchema.partial().parse(req.body) });
    res.json(zoneDto(zone));
  }),
);

// ---- Categories ----

const categorySchema = z.object({
  slug: z.string().trim().regex(/^[a-z0-9-]+$/),
  nameEn: z.string().trim().min(1).max(80),
  nameFr: z.string().trim().min(1).max(80),
  imageUrl: z.string().url().nullish(),
  parentId: z.string().nullish(),
  position: z.number().int().default(0),
  sizeType: z.nativeEnum(SizeType).nullish(),
  icon: z.string().trim().max(40).nullish(),
});

contentAdminRouter.post(
  '/categories',
  ah(async (req, res) => {
    const category = await prisma.category.create({ data: categorySchema.parse(req.body), include: { parent: true } });
    res.status(201).json(categoryDto(category));
  }),
);

contentAdminRouter.patch(
  '/categories/:id',
  ah(async (req, res) => {
    const category = await prisma.category.update({
      where: { id: req.params.id },
      data: categorySchema.partial().parse(req.body),
      include: { parent: true },
    });
    res.json(categoryDto(category));
  }),
);

/** Only an empty category can be deleted: move or archive its products first. */
contentAdminRouter.delete(
  '/categories/:id',
  ah(async (req, res) => {
    const category = await prisma.category.findUnique({
      where: { id: req.params.id },
      include: { _count: { select: { products: true, children: true } } },
    });
    if (!category) throw notFound();
    if (category._count.products > 0 || category._count.children > 0) throw new AppError(409, 'category_not_empty');
    await prisma.category.delete({ where: { id: category.id } });
    res.status(204).end();
  }),
);
