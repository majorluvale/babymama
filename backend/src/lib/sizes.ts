import type { Category, SizeType } from '@prisma/client';

/** Sizes offered for each scale, in display order. The apps get them through each category's `sizes`. */
export const sizeScales: Record<SizeType, string[]> = {
  CLOTHING: ['XS', 'S', 'M', 'L', 'XL', 'XXL', '3XL'],
  KIDS_AGE: ['0-3M', '3-6M', '6-12M', '12-18M', '18-24M', '2Y', '3Y', '4Y', '5Y', '6Y', '7Y', '8Y', '10Y', '12Y', '14Y'],
  SHOES: Array.from({ length: 31 }, (_, i) => String(16 + i)), // EU 16 to 46
  ONE_SIZE: [],
};

/** Colour keys; the apps translate them (color_black...). Keep in sync with packages/babymama_core/lib/src/catalog_options.dart. */
export const colors = [
  'black', 'white', 'grey', 'beige', 'brown', 'navy', 'blue', 'green',
  'red', 'pink', 'purple', 'yellow', 'orange', 'multicolor',
] as const;

/** A category without its own scale uses its parent's. */
export function effectiveSizeType(c: Pick<Category, 'sizeType'> & { parent?: Pick<Category, 'sizeType'> | null }): SizeType | null {
  return c.sizeType ?? c.parent?.sizeType ?? null;
}
