import type { Role } from '@prisma/client';

declare global {
  namespace Express {
    interface Request {
      user?: { id: string; role: Role; name: string; email: string };
      /** Raw request body, kept for webhook signature checks. */
      rawBody?: Buffer;
    }
  }
}

export {};
