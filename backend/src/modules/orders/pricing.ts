export interface PriceLine {
  kind: 'product' | 'bundle';
  unitPrice: number;
  quantity: number;
}

export interface Tier {
  minItems: number;
  percent: number;
}

export interface Totals {
  subtotal: number;
  discount: number;
  discountPercent: number;
  deliveryFee: number;
  total: number;
  /** Number of individual articles (bundles excluded) used for the multi-buy discount. */
  itemCount: number;
  nextTier: Tier | null;
}

/**
 * Multi-buy discount ("achat groupé"): the more single items in the cart, the bigger the discount.
 * Bundles already have a reduced price, so they are not discounted again.
 */
export function computeTotals(lines: PriceLine[], tiers: Tier[], deliveryFee: number): Totals {
  const subtotal = lines.reduce((s, l) => s + l.unitPrice * l.quantity, 0);
  const productLines = lines.filter((l) => l.kind === 'product');
  const itemCount = productLines.reduce((s, l) => s + l.quantity, 0);
  const productSubtotal = productLines.reduce((s, l) => s + l.unitPrice * l.quantity, 0);

  const sorted = [...tiers].sort((a, b) => a.minItems - b.minItems);
  const applicable = sorted.filter((t) => itemCount >= t.minItems);
  const best = applicable.reduce<Tier | null>((acc, t) => (!acc || t.percent > acc.percent ? t : acc), null);
  const nextTier = sorted.find((t) => t.minItems > itemCount && t.percent > (best?.percent ?? 0)) ?? null;

  const discountPercent = best?.percent ?? 0;
  const discount = Math.round((productSubtotal * discountPercent) / 100);
  return {
    subtotal,
    discount,
    discountPercent,
    deliveryFee,
    total: subtotal - discount + deliveryFee,
    itemCount,
    nextTier,
  };
}
