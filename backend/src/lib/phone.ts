/** Kenyan phone helpers, shared by payments (M-Pesa / Airtel) and SMS sign-in. */

/** Normalises a Kenyan number to the 2547******** / 2541******** form, or null if it is not one. */
export function normalizeKenyanPhone(input: string): string | null {
  const digits = input.replace(/\D/g, '');
  if (/^254[17]\d{8}$/.test(digits)) return digits;
  if (/^0[17]\d{8}$/.test(digits)) return `254${digits.slice(1)}`;
  if (/^[17]\d{8}$/.test(digits)) return `254${digits}`;
  return null;
}

/** Every stored form that could match a normalised number, so a lookup finds users saved as 07.. or 2547.. */
export function phoneVariants(normalized: string): string[] {
  const local = `0${normalized.slice(3)}`; // 07.. / 01..
  return [normalized, `+${normalized}`, local, normalized.slice(3)];
}
