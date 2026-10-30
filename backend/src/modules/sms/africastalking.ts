import type { SmsSettings } from './settings';

/** Africa's Talking SMS API. The "sandbox" username uses the sandbox host. */
const host = (username: string) =>
  username === 'sandbox' ? 'https://api.sandbox.africastalking.com' : 'https://api.africastalking.com';

/** Sends one SMS. Throws on a transport or API error. */
export async function sendViaAfricasTalking(to: string, message: string, s: SmsSettings): Promise<void> {
  const body = new URLSearchParams({ username: s.africasTalking.username, to, message });
  if (s.senderId) body.set('from', s.senderId);

  const res = await fetch(`${host(s.africasTalking.username)}/version1/messaging`, {
    method: 'POST',
    headers: {
      apiKey: s.africasTalking.apiKey,
      'Content-Type': 'application/x-www-form-urlencoded',
      Accept: 'application/json',
    },
    body,
  });
  const data = (await res.json().catch(() => ({}))) as {
    SMSMessageData?: { Recipients?: { status?: string; statusCode?: number }[] };
  };
  if (!res.ok) throw new Error(`Africa's Talking error (${res.status})`);
  const recipient = data.SMSMessageData?.Recipients?.[0];
  // 100 = processed, 101 = sent, 102 = queued. Anything else is a failure.
  if (recipient && recipient.statusCode && ![100, 101, 102].includes(recipient.statusCode)) {
    throw new Error(recipient.status ?? "Africa's Talking rejected the message");
  }
}

/** Sign-in check used by the admin "test" button: verifies the keys are accepted without sending an SMS. */
export async function checkAfricasTalking(s: SmsSettings): Promise<boolean> {
  const res = await fetch(`${host(s.africasTalking.username)}/version1/user?username=${encodeURIComponent(s.africasTalking.username)}`, {
    headers: { apiKey: s.africasTalking.apiKey, Accept: 'application/json' },
  });
  return res.ok;
}
