import { describe, expect, it } from 'vitest';
import { computeTotals } from './pricing';

const tiers = [
  { minItems: 2, percent: 5 },
  { minItems: 3, percent: 10 },
  { minItems: 5, percent: 15 },
];

describe('computeTotals', () => {
  it('applies no discount to a single item', () => {
    const t = computeTotals([{ kind: 'product', unitPrice: 800, quantity: 1 }], tiers, 200);
    expect(t).toMatchObject({ subtotal: 800, discount: 0, total: 1000, itemCount: 1 });
    expect(t.nextTier).toEqual({ minItems: 2, percent: 5 });
  });

  it('applies the best reached tier on single items only', () => {
    const t = computeTotals(
      [
        { kind: 'product', unitPrice: 1000, quantity: 3 },
        { kind: 'bundle', unitPrice: 2500, quantity: 1 },
      ],
      tiers,
      250,
    );
    expect(t.discountPercent).toBe(10);
    expect(t.discount).toBe(300);
    expect(t.total).toBe(3000 + 2500 - 300 + 250);
    expect(t.nextTier).toEqual({ minItems: 5, percent: 15 });
  });

  it('has no next tier once the top tier is reached', () => {
    const t = computeTotals([{ kind: 'product', unitPrice: 500, quantity: 6 }], tiers, 0);
    expect(t.discountPercent).toBe(15);
    expect(t.nextTier).toBeNull();
  });
});
