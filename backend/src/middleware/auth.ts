import type { RequestHandler } from 'express';
import jwt from 'jsonwebtoken';
import type { Role } from '@prisma/client';
import { config } from '../config';
import { AppError } from '../lib/errors';
import { prisma } from '../lib/prisma';

function authenticate(required: boolean): RequestHandler {
  return (req, _res, next) => {
    const header = req.header('authorization');
    const token = header?.startsWith('Bearer ') ? header.slice(7) : undefined;
    const fail = () => (required ? next(new AppError(401, 'unauthorized')) : next());
    if (!token) return fail();

    let userId: string | undefined;
    try {
      const payload = jwt.verify(token, config.jwtSecret) as jwt.JwtPayload;
      userId = typeof payload.sub === 'string' ? payload.sub : undefined;
    } catch {
      userId = undefined;
    }
    if (!userId) return fail();

    prisma.user
      .findUnique({ where: { id: userId }, select: { id: true, role: true, name: true, email: true, isActive: true } })
      .then((user) => {
        if (!user || !user.isActive) return fail();
        req.user = { id: user.id, role: user.role, name: user.name, email: user.email };
        next();
      })
      .catch(next);
  };
}

export const requireAuth = authenticate(true);
export const optionalAuth = authenticate(false);

export function requireRole(...roles: Role[]): RequestHandler {
  return (req, _res, next) => {
    if (!req.user) return next(new AppError(401, 'unauthorized'));
    if (!roles.includes(req.user.role)) return next(new AppError(403, 'forbidden'));
    next();
  };
}

export const isStaff = (role?: Role) => role === 'ADMIN' || role === 'SUPPORT';
