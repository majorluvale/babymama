import crypto from 'node:crypto';
import { config } from '../config';

/** AES-256-GCM for secrets stored in the database (payment API keys). Key: SETTINGS_SECRET, else JWT_SECRET. */
const key = () => crypto.createHash('sha256').update(config.settingsSecret).digest();

const PREFIX = 'enc:v1:';

export function encryptSecret(plain: string): string {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key(), iv);
  const data = Buffer.concat([cipher.update(plain, 'utf8'), cipher.final()]);
  return PREFIX + [iv, cipher.getAuthTag(), data].map((b) => b.toString('base64')).join(':');
}

/** Returns '' when the value cannot be decrypted (for example after the key changed): the admin re-enters it. */
export function decryptSecret(stored: string): string {
  if (!stored.startsWith(PREFIX)) return stored;
  try {
    const [iv, tag, data] = stored.slice(PREFIX.length).split(':').map((p) => Buffer.from(p, 'base64'));
    const decipher = crypto.createDecipheriv('aes-256-gcm', key(), iv);
    decipher.setAuthTag(tag);
    return Buffer.concat([decipher.update(data), decipher.final()]).toString('utf8');
  } catch {
    console.error('[settings] a stored secret could not be decrypted; re-enter it in the admin');
    return '';
  }
}
