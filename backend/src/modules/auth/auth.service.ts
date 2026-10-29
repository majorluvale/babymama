import jwt from 'jsonwebtoken';
import { OAuth2Client } from 'google-auth-library';
import type { User } from '@prisma/client';
import { config } from '../../config';
import { userDto } from '../../lib/dto';
import { AppError } from '../../lib/errors';
import { prisma } from '../../lib/prisma';

const googleClient = new OAuth2Client();

export function signToken(user: Pick<User, 'id' | 'role'>): string {
  return jwt.sign({ sub: user.id, role: user.role }, config.jwtSecret, { expiresIn: config.jwtExpiresInSeconds });
}

export function authResponse(user: User) {
  return { token: signToken(user), user: userDto(user) };
}

interface GoogleIdentity {
  googleId: string;
  email: string;
  name: string;
  picture?: string;
}

/**
 * Accepts either an ID token (Android / iOS) or an access token (Flutter web, where
 * google_sign_in does not always return an ID token).
 */
export async function verifyGoogle(input: { idToken?: string | null; accessToken?: string | null }): Promise<GoogleIdentity> {
  const audiences = config.google.clientIds;
  try {
    if (input.idToken) {
      const ticket = await googleClient.verifyIdToken({
        idToken: input.idToken,
        audience: audiences.length ? audiences : undefined,
      });
      const p = ticket.getPayload();
      if (!p?.email || !p.email_verified) throw new Error('email not verified');
      return { googleId: p.sub, email: p.email.toLowerCase(), name: p.name ?? p.email, picture: p.picture };
    }
    if (input.accessToken) {
      const info = await googleClient.getTokenInfo(input.accessToken);
      if (audiences.length && (!info.aud || !audiences.includes(info.aud))) throw new Error('bad audience');
      const res = await fetch('https://www.googleapis.com/oauth2/v3/userinfo', {
        headers: { Authorization: `Bearer ${input.accessToken}` },
      });
      if (!res.ok) throw new Error(`userinfo ${res.status}`);
      const u = (await res.json()) as { sub: string; email?: string; email_verified?: boolean; name?: string; picture?: string };
      if (!u.email || !u.email_verified) throw new Error('email not verified');
      return { googleId: u.sub, email: u.email.toLowerCase(), name: u.name ?? u.email, picture: u.picture };
    }
  } catch (e) {
    console.warn('[google] verification failed:', (e as Error).message);
  }
  throw new AppError(401, 'google_auth_failed');
}

export async function loginWithGoogle(identity: GoogleIdentity, locale?: string): Promise<User> {
  let user = await prisma.user.findUnique({ where: { googleId: identity.googleId } });
  if (!user) {
    const byEmail = await prisma.user.findUnique({ where: { email: identity.email } });
    user = byEmail
      ? await prisma.user.update({
          where: { id: byEmail.id },
          data: { googleId: identity.googleId, avatarUrl: byEmail.avatarUrl ?? identity.picture },
        })
      : await prisma.user.create({
          data: {
            email: identity.email,
            name: identity.name,
            googleId: identity.googleId,
            avatarUrl: identity.picture,
            locale: locale ?? 'en',
          },
        });
  }
  if (!user.isActive) throw new AppError(403, 'account_disabled');
  return user;
}
