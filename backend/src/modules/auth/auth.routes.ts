import { Router } from 'express';
import bcrypt from 'bcryptjs';
import rateLimit from 'express-rate-limit';
import { z } from 'zod';
import { userDto } from '../../lib/dto';
import { AppError, notFound } from '../../lib/errors';
import { ah } from '../../lib/http';
import { prisma } from '../../lib/prisma';
import { requireAuth } from '../../middleware/auth';
import { authResponse, loginWithGoogle, verifyGoogle } from './auth.service';

export const authRouter = Router();

// Only failed attempts count, so brute force is slowed down without locking out people who sign in normally.
const limiter = rateLimit({ windowMs: 15 * 60 * 1000, limit: 20, skipSuccessfulRequests: true, standardHeaders: true, legacyHeaders: false });

const locale = z.enum(['en', 'fr']);

const registerSchema = z.object({
  name: z.string().trim().min(2).max(80),
  email: z.string().trim().toLowerCase().email(),
  password: z.string().min(8).max(100),
  phone: z.string().trim().max(20).optional(),
  locale: locale.optional(),
});

authRouter.post(
  '/register',
  limiter,
  ah(async (req, res) => {
    const body = registerSchema.parse(req.body);
    const exists = await prisma.user.findUnique({ where: { email: body.email } });
    if (exists) throw new AppError(409, 'email_taken');
    const user = await prisma.user.create({
      data: {
        name: body.name,
        email: body.email,
        phone: body.phone,
        locale: body.locale ?? 'en',
        passwordHash: await bcrypt.hash(body.password, 10),
      },
    });
    res.status(201).json(authResponse(user));
  }),
);

const loginSchema = z.object({
  email: z.string().trim().toLowerCase().email(),
  password: z.string().min(1),
});

authRouter.post(
  '/login',
  limiter,
  ah(async (req, res) => {
    const body = loginSchema.parse(req.body);
    const user = await prisma.user.findUnique({ where: { email: body.email } });
    if (!user?.passwordHash || !(await bcrypt.compare(body.password, user.passwordHash))) {
      throw new AppError(401, 'invalid_credentials');
    }
    if (!user.isActive) throw new AppError(403, 'account_disabled');
    res.json(authResponse(user));
  }),
);

const googleSchema = z
  .object({ idToken: z.string().nullish(), accessToken: z.string().nullish(), locale: locale.optional() })
  .refine((v) => v.idToken || v.accessToken, { message: 'idToken or accessToken required' });

authRouter.post(
  '/google',
  limiter,
  ah(async (req, res) => {
    const body = googleSchema.parse(req.body);
    const identity = await verifyGoogle(body);
    const user = await loginWithGoogle(identity, body.locale);
    res.json(authResponse(user));
  }),
);

authRouter.get(
  '/me',
  requireAuth,
  ah(async (req, res) => {
    const user = await prisma.user.findUniqueOrThrow({ where: { id: req.user!.id } });
    res.json(userDto(user));
  }),
);

const profileSchema = z.object({
  name: z.string().trim().min(2).max(80).optional(),
  phone: z.string().trim().max(20).nullish(),
  locale: locale.optional(),
  avatarUrl: z.string().url().nullish(),
});

authRouter.patch(
  '/me',
  requireAuth,
  ah(async (req, res) => {
    const data = profileSchema.parse(req.body);
    const user = await prisma.user.update({ where: { id: req.user!.id }, data });
    res.json(userDto(user));
  }),
);

const passwordSchema = z.object({ currentPassword: z.string().optional(), newPassword: z.string().min(8).max(100) });

authRouter.post(
  '/change-password',
  requireAuth,
  ah(async (req, res) => {
    const body = passwordSchema.parse(req.body);
    const user = await prisma.user.findUniqueOrThrow({ where: { id: req.user!.id } });
    // Google-only accounts can set a first password without the current one.
    if (user.passwordHash && !(await bcrypt.compare(body.currentPassword ?? '', user.passwordHash))) {
      throw new AppError(400, 'wrong_password');
    }
    await prisma.user.update({ where: { id: user.id }, data: { passwordHash: await bcrypt.hash(body.newPassword, 10) } });
    res.json({ ok: true });
  }),
);

// ---- Saved delivery addresses ----

const addressSchema = z.object({
  label: z.string().trim().max(40).default('Home'),
  recipientName: z.string().trim().min(2).max(80),
  phone: z.string().trim().min(9).max(20),
  zoneId: z.string(),
  street: z.string().trim().min(3).max(200),
  landmark: z.string().trim().max(200).nullish(),
  lat: z.number().nullish(),
  lng: z.number().nullish(),
  isDefault: z.boolean().default(false),
});

authRouter.get(
  '/me/addresses',
  requireAuth,
  ah(async (req, res) => {
    const addresses = await prisma.address.findMany({
      where: { userId: req.user!.id },
      include: { zone: true },
      orderBy: [{ isDefault: 'desc' }, { createdAt: 'desc' }],
    });
    res.json(addresses);
  }),
);

authRouter.post(
  '/me/addresses',
  requireAuth,
  ah(async (req, res) => {
    const data = addressSchema.parse(req.body);
    const userId = req.user!.id;
    if (data.isDefault) await prisma.address.updateMany({ where: { userId }, data: { isDefault: false } });
    const address = await prisma.address.create({ data: { ...data, userId }, include: { zone: true } });
    res.status(201).json(address);
  }),
);

authRouter.delete(
  '/me/addresses/:id',
  requireAuth,
  ah(async (req, res) => {
    const deleted = await prisma.address.deleteMany({ where: { id: req.params.id, userId: req.user!.id } });
    if (!deleted.count) throw notFound();
    res.status(204).end();
  }),
);
