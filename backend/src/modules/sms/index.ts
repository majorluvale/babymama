import { AppError } from '../../lib/errors';
import { sendViaAfricasTalking } from './africastalking';
import { getSmsSettings, smsReady } from './settings';

/**
 * Sends an SMS through the configured gateway.
 * In simulation mode the message is only logged. Returns whether it was really sent.
 */
export async function sendSms(to: string, message: string): Promise<{ sent: boolean; mock: boolean }> {
  const s = await getSmsSettings();
  if (s.mock) {
    console.log(`[sms:mock] to ${to}: ${message}`);
    return { sent: false, mock: true };
  }
  if (!smsReady(s)) throw new AppError(503, 'sms_not_configured');
  await sendViaAfricasTalking(to, message, s);
  return { sent: true, mock: false };
}

export { getSmsSettings, smsReady } from './settings';
