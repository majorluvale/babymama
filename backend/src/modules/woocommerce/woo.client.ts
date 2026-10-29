import { config } from '../../config';

/** Minimal WooCommerce REST API v3 client (consumer key / secret over HTTPS). */

export interface WooProduct {
  id: number;
  name: string;
  slug: string;
  sku: string;
  status: string;
  description: string;
  short_description: string;
  price: string;
  regular_price: string;
  sale_price: string;
  manage_stock: boolean;
  stock_quantity: number | null;
  stock_status: string;
  images: { src: string }[];
  categories: { id: number; name: string; slug: string }[];
  attributes: { name: string; options: string[] }[];
}

export const wooEnabled = () => Boolean(config.woo.url && config.woo.consumerKey && config.woo.consumerSecret);

export async function wooFetch<T>(
  path: string,
  init: { method?: string; body?: unknown; query?: Record<string, string | number> } = {},
): Promise<T> {
  const url = new URL(`${config.woo.url}/wp-json/wc/v3${path}`);
  for (const [k, v] of Object.entries(init.query ?? {})) url.searchParams.set(k, String(v));
  const auth = Buffer.from(`${config.woo.consumerKey}:${config.woo.consumerSecret}`).toString('base64');
  const res = await fetch(url, {
    method: init.method ?? 'GET',
    headers: { Authorization: `Basic ${auth}`, 'Content-Type': 'application/json' },
    body: init.body === undefined ? undefined : JSON.stringify(init.body),
  });
  if (!res.ok) throw new Error(`WooCommerce ${init.method ?? 'GET'} ${path} failed: ${res.status} ${await res.text()}`);
  return (await res.json()) as T;
}
