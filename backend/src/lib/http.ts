import type { NextFunction, Request, RequestHandler, Response } from 'express';
import { z } from 'zod';

/** Wraps an async route handler so rejected promises reach the error middleware. */
export const ah =
  (fn: (req: Request, res: Response, next: NextFunction) => Promise<unknown>): RequestHandler =>
  (req, res, next) => {
    fn(req, res, next).catch(next);
  };

export const pageQuery = z.object({
  page: z.coerce.number().int().min(1).default(1),
  pageSize: z.coerce.number().int().min(1).max(100).default(24),
});

export function paged<T>(items: T[], total: number, page: number, pageSize: number) {
  return { items, total, page, pageSize, pages: Math.max(1, Math.ceil(total / pageSize)) };
}

export const skipTake = (page: number, pageSize: number) => ({ skip: (page - 1) * pageSize, take: pageSize });
