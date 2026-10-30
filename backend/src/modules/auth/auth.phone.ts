import crypto from 'node:crypto';
import bcrypt from 'bcryptjs';
import type { User } from '@prisma/client';
import { AppError } from '../../lib/errors';
import { normalizeKenyanPhone, phoneVariants } from '../../lib/phone';
import { prisma } from '../../lib/prisma';
import { getSmsSettings, sendSms } from '../sms';

const CODE_TTL_MS = 5 * 60_000;
const RESEND_COOLDOWN_MS = 45_000;
const MAX_ATTEMPTS = 5;

const message = (code: string, lang: string) =>
  lang === 'fr' ? `Babymama : votre code de connexion est ${code}. Il expire dans 5 min.` : `Babymama: your sign-in code is ${code}. It expires in 5 min.`;

/** Sends a fresh code to a Kenyan number. Returns the code only in simulation mode (development). */
export async function requestPhoneOtp(rawPhone: string, lang: string): Promise<{ devCode?: string }> {
  const phone = normalizeKenyanPhone(rawPhone);
  if (!phone) throw new AppError(400, 'phone_required');

  const recent = await prisma.phoneOtp.findFirst({ where: { phone }, orderBy: { createdAt: 'desc' } });
  if (recent && Date.now() - recent.createdAt.getTime() < RESEND_COOLDOWN_MS) {
    throw new AppError(429, 'too_many_attempts');
  }

  const code = crypto.randomInt(0, 1_000_000).toString().padStart(6, '0');
  await prisma.phoneOtp.deleteMany({ where: { phone } });
  await prisma.phoneOtp.create({
    data: { phone, codeHash: await bcrypt.hash(code, 10), expiresAt: new Date(Date.now() + CODE_TTL_MS) },
  });

  const { mock } = await sendSms(phone, message(code, lang));
  // The code travels by SMS; it is returned only when sending is simulated, so a developer can test.
  return mock ? { devCode: code } : {};
}

/** Verifies a code and signs the person in, creating the account on first use. */
export async function verifyPhoneOtp(rawPhone: string, code: string, name: string | undefined, locale: string | undefined): Promise<User> {
  const phone = normalizeKenyanPhone(rawPhone);
  if (!phone) throw new AppError(400, 'phone_required');

  const otp = await prisma.phoneOtp.findFirst({ where: { phone }, orderBy: { createdAt: 'desc' } });
  if (!otp || otp.expiresAt < new Date()) throw new AppError(400, 'invalid_code');
  if (otp.attempts >= MAX_ATTEMPTS) {
    await prisma.phoneOtp.deleteMany({ where: { phone } });
    throw new AppError(429, 'too_many_attempts');
  }
  if (!(await bcrypt.compare(code, otp.codeHash))) {
    await prisma.phoneOtp.update({ where: { id: otp.id }, data: { attempts: { increment: 1 } } });
    throw new AppError(400, 'invalid_code');
  }
  await prisma.phoneOtp.deleteMany({ where: { phone } });

  const existing = await prisma.user.findFirst({ where: { phone: { in: phoneVariants(phone) } }, orderBy: { createdAt: 'asc' } });
  if (existing) {
    if (!existing.isActive) throw new AppError(403, 'account_disabled');
    return existing;
  }
  return prisma.user.create({
    data: { phone, name: name?.trim() || `+${phone}`, email: `phone+${phone}@babymama.local`, locale: locale ?? 'en' },
  });
}

/** Whether phone sign-in can be offered (a gateway is set up, or simulation is on). */
export async function phoneSignInAvailable(): Promise<boolean> {
  const s = await getSmsSettings();
  return s.mock || Boolean(s.africasTalking.username && s.africasTalking.apiKey);
}
