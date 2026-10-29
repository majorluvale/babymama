import type { ErrorRequestHandler, RequestHandler } from 'express';
import { Prisma } from '@prisma/client';
import multer from 'multer';
import { ZodError } from 'zod';
import { langFrom, t } from './i18n';

/** Error with an HTTP status and a translatable code (see lib/i18n.ts). */
export class AppError extends Error {
  constructor(
    public readonly status: number,
    public readonly code: string,
    public readonly details?: unknown,
  ) {
    super(code);
  }
}

export const notFound = () => new AppError(404, 'not_found');

export const notFoundHandler: RequestHandler = (_req, _res, next) => next(notFound());

export const errorHandler: ErrorRequestHandler = (err, req, res, _next) => {
  const lang = langFrom(req.header('accept-language'));

  if (err instanceof ZodError) {
    const first = err.issues[0];
    res.status(400).json({
      error: 'validation_error',
      message: `${t(lang, 'validation_error')}${first ? ` (${first.path.join('.')}: ${first.message})` : ''}`,
      issues: err.issues.map((i) => ({ path: i.path.join('.'), message: i.message })),
    });
    return;
  }
  if (err instanceof AppError) {
    res.status(err.status).json({ error: err.code, message: t(lang, err.code), details: err.details });
    return;
  }
  if (err instanceof Prisma.PrismaClientKnownRequestError) {
    if (err.code === 'P2002') {
      res.status(409).json({ error: 'conflict', message: t(lang, 'conflict') });
      return;
    }
    if (err.code === 'P2025') {
      res.status(404).json({ error: 'not_found', message: t(lang, 'not_found') });
      return;
    }
  }
  if (err instanceof multer.MulterError) {
    res.status(400).json({ error: 'invalid_file', message: `${t(lang, 'invalid_file')} (${err.message})` });
    return;
  }
  if (err?.type === 'entity.parse.failed') {
    res.status(400).json({ error: 'validation_error', message: t(lang, 'validation_error') });
    return;
  }

  console.error(err);
  res.status(500).json({ error: 'internal_error', message: t(lang, 'internal_error') });
};
