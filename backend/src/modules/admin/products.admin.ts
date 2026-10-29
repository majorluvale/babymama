import { Router } from 'express';
import { Prisma, ProductCondition, ProductStatus } from '@prisma/client';
import { z } from 'zod';
import { productDto, productInclude } from '../../lib/dto';
import { AppError, notFound } from '../../lib/errors';
import { ah, pageQuery, paged, skipTake } from '../../lib/http';
import { prisma } from '../../lib/prisma';
import { effectiveSizeType, sizeScales } from '../../lib/sizes';
import { adjustStock } from '../stock/stock.service';
import { pushProductToWoo, pushStockToWoo } from '../woocommerce/woo.sync';

/** Products + stock management for the admin back-office. */
export const productsAdminRouter = Router();

const generateSku = () =>
  `BM-${Date.now().toString(36).toUpperCase()}${Math.floor(Math.random() * 1296)
    .toString(36)
    .toUpperCase()
    .padStart(2, '0')}`;

const productFields = z.object({
  title: z.string().trim().min(2).max(140),
  description: z.string().max(5000).default(''),
  brand: z.string().trim().max(80).nullish(),
  size: z.string().trim().max(40).nullish(),
  color: z.string().trim().max(40).nullish(),
  condition: z.nativeEnum(ProductCondition).default('GOOD'),
  price: z.number().int().min(0),
  compareAtPrice: z.number().int().min(0).nullish(),
  categoryId: z.string().nullish(),
  sku: z.string().trim().min(2).max(60).optional(),
  images: z.array(z.string().url()).max(12).default([]),
  status: z.nativeEnum(ProductStatus).default('ACTIVE'),
  isFeatured: z.boolean().default(false),
  lowStockThreshold: z.number().int().min(0).default(1),
  rejectReason: z.string().max(300).nullish(),
});

/** The size must belong to the category's scale: S/M/L for clothes, age for kids, EU number for shoes, none for accessories. */
async function assertSize(categoryId: string | null | undefined, size: string | null | undefined) {
  if (!categoryId || !size) return;
  const category = await prisma.category.findUnique({ where: { id: categoryId }, include: { parent: true } });
  const sizeType = category && effectiveSizeType(category);
  if (sizeType && !sizeScales[sizeType].includes(size)) throw new AppError(400, 'invalid_size', { sizes: sizeScales[sizeType] });
}

const createSchema = productFields.extend({ stock: z.number().int().min(0).default(1) });
const updateSchema = productFields.partial();

const listQuery = pageQuery.extend({
  q: z.string().trim().optional(),
  status: z.nativeEnum(ProductStatus).optional(),
  lowStock: z.enum(['true', 'false']).optional(),
  source: z.enum(['ADMIN', 'SELLER', 'WOOCOMMERCE']).optional(),
});

productsAdminRouter.get(
  '/products',
  ah(async (req, res) => {
    const q = listQuery.parse(req.query);
    const where: Prisma.ProductWhereInput = {};
    if (q.status) where.status = q.status;
    if (q.source) where.source = q.source;
    if (q.lowStock === 'true') where.stock = { lte: prisma.product.fields.lowStockThreshold };
    if (q.q) {
      where.OR = [
        { title: { contains: q.q, mode: 'insensitive' } },
        { sku: { contains: q.q, mode: 'insensitive' } },
        { brand: { contains: q.q, mode: 'insensitive' } },
      ];
    }
    const [items, total] = await Promise.all([
      prisma.product.findMany({ where, include: productInclude, orderBy: { updatedAt: 'desc' }, ...skipTake(q.page, q.pageSize) }),
      prisma.product.count({ where }),
    ]);
    res.json(paged(items.map((p) => productDto(p)), total, q.page, q.pageSize));
  }),
);

productsAdminRouter.get(
  '/products/:id',
  ah(async (req, res) => {
    const p = await prisma.product.findUnique({ where: { id: req.params.id }, include: productInclude });
    if (!p) throw notFound();
    res.json(productDto(p));
  }),
);

productsAdminRouter.post(
  '/products',
  ah(async (req, res) => {
    const { images, stock, sku, ...data } = createSchema.parse(req.body);
    await assertSize(data.categoryId, data.size);
    const userId = req.user!.id;
    const product = await prisma.product.create({
      data: {
        ...data,
        sku: sku || generateSku(),
        stock,
        status: data.status === 'ACTIVE' && stock === 0 ? 'SOLD_OUT' : data.status,
        source: 'ADMIN',
        images: { create: images.map((url, position) => ({ url, position })) },
        movements:
          stock > 0 ? { create: { type: 'RESTOCK', quantity: stock, stockAfter: stock, userId, reason: 'Initial stock' } } : undefined,
      },
      include: productInclude,
    });
    void pushProductToWoo(product.id);
    res.status(201).json(productDto(product));
  }),
);

productsAdminRouter.patch(
  '/products/:id',
  ah(async (req, res) => {
    const { images, ...data } = updateSchema.parse(req.body);
    if (data.size !== undefined || data.categoryId !== undefined) {
      const current = await prisma.product.findUnique({ where: { id: req.params.id } });
      if (!current) throw notFound();
      await assertSize(data.categoryId !== undefined ? data.categoryId : current.categoryId, data.size !== undefined ? data.size : current.size);
    }
    const product = await prisma.product.update({
      where: { id: req.params.id },
      data: {
        ...data,
        ...(images ? { images: { deleteMany: {}, create: images.map((url, position) => ({ url, position })) } } : {}),
      },
      include: productInclude,
    });
    res.json(productDto(product));
  }),
);

/** Products are archived, never deleted, to keep order history and the stock ledger intact. */
productsAdminRouter.delete(
  '/products/:id',
  ah(async (req, res) => {
    await prisma.product.update({ where: { id: req.params.id }, data: { status: 'ARCHIVED', isFeatured: false } });
    res.status(204).end();
  }),
);

const adjustSchema = z
  .object({
    type: z.enum(['RESTOCK', 'ADJUSTMENT', 'RETURN']),
    quantity: z.number().int().refine((n) => n !== 0, 'quantity must not be 0'),
    reason: z.string().trim().max(200).optional(),
  })
  .refine((v) => v.type === 'ADJUSTMENT' || v.quantity > 0, { message: 'quantity must be positive', path: ['quantity'] });

productsAdminRouter.post(
  '/products/:id/stock',
  ah(async (req, res) => {
    const body = adjustSchema.parse(req.body);
    await adjustStock(req.params.id, body.quantity, body.type, req.user!.id, body.reason);
    void pushStockToWoo([req.params.id]);
    const p = await prisma.product.findUniqueOrThrow({ where: { id: req.params.id }, include: productInclude });
    res.json(productDto(p));
  }),
);

productsAdminRouter.get(
  '/stock/movements',
  ah(async (req, res) => {
    const q = pageQuery.extend({ productId: z.string().optional() }).parse(req.query);
    const where: Prisma.StockMovementWhereInput = q.productId ? { productId: q.productId } : {};
    const [items, total] = await Promise.all([
      prisma.stockMovement.findMany({
        where,
        include: {
          product: { select: { id: true, title: true, sku: true } },
          user: { select: { name: true } },
          order: { select: { seq: true } },
        },
        orderBy: { createdAt: 'desc' },
        ...skipTake(q.page, q.pageSize),
      }),
      prisma.stockMovement.count({ where }),
    ]);
    res.json(paged(items, total, q.page, q.pageSize));
  }),
);

productsAdminRouter.get(
  '/stock/summary',
  ah(async (_req, res) => {
    const [inStock, soldOut, lowStock, units, value] = await Promise.all([
      prisma.product.count({ where: { status: 'ACTIVE' } }),
      prisma.product.count({ where: { status: 'SOLD_OUT' } }),
      prisma.product.count({
        where: { status: { in: ['ACTIVE', 'SOLD_OUT'] }, stock: { lte: prisma.product.fields.lowStockThreshold } },
      }),
      prisma.product.aggregate({ where: { status: { in: ['ACTIVE', 'SOLD_OUT'] } }, _sum: { stock: true } }),
      prisma.$queryRaw<{ value: bigint | null }[]>`SELECT SUM("stock" * "price") AS value FROM "Product" WHERE "status" = 'ACTIVE'`,
    ]);
    res.json({
      activeProducts: inStock,
      soldOut,
      lowStock,
      totalUnits: units._sum.stock ?? 0,
      stockValue: Number(value[0]?.value ?? 0),
    });
  }),
);
