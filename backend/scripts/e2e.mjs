// End-to-end check of the whole API against a seeded database.
// Usage: start the API (npm run dev, PAYMENTS_MOCK=true), run `npm run db:seed`, then `npm run e2e`.
// Optional: API_URL=http://localhost:4000
// Auth routes allow 20 failed attempts per 15 min per IP; each run makes 3, so about six runs in a row get 429s.
import { PrismaClient } from '@prisma/client';

const API = `${process.env.API_URL ?? 'http://localhost:4000'}/api`;
const prisma = new PrismaClient();
let passed = 0;
const failures = [];

function check(name, condition, info) {
  if (condition) passed++;
  else failures.push(`${name}${info === undefined ? '' : ` -> ${JSON.stringify(info).slice(0, 400)}`}`);
}

async function call(method, path, { token, body, lang } = {}) {
  const res = await fetch(`${API}${path}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(lang ? { 'Accept-Language': lang } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  let data = null;
  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    data = text;
  }
  return { status: res.status, data };
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const login = async (email, password) => (await call('POST', '/auth/login', { body: { email, password } })).data?.token;
const stockOf = async (id) => (await prisma.product.findUnique({ where: { id } })).stock;

async function main() {
  // ---------- Auth ----------
  const customer = await login('customer@babymama.co.ke', 'Customer123!');
  const admin = await login('admin@babymama.co.ke', process.env.SEED_ADMIN_PASSWORD ?? 'ChangeMe123!');
  const rider = await login('rider@babymama.co.ke', 'Rider123!');
  const support = await login('support@babymama.co.ke', 'Support123!');
  check('logins', customer && admin && rider && support);

  const badLogin = await call('POST', '/auth/login', { body: { email: 'customer@babymama.co.ke', password: 'nope' }, lang: 'fr' });
  check('wrong password -> 401 in French', badLogin.status === 401 && badLogin.data.message.includes('incorrect'), badLogin);

  const email = `test${Date.now()}@example.com`;
  const reg = await call('POST', '/auth/register', { body: { name: 'Test User', email, password: 'Password123', locale: 'fr' } });
  check('register', reg.status === 201 && reg.data.token && reg.data.user.locale === 'fr', reg);
  const dup = await call('POST', '/auth/register', { body: { name: 'Test User', email, password: 'Password123' } });
  check('duplicate e-mail -> 409', dup.status === 409, dup);
  const me = await call('GET', '/auth/me', { token: customer });
  check('me', me.data?.role === 'CUSTOMER', me);
  const googleBad = await call('POST', '/auth/google', { body: { idToken: 'not-a-token' } });
  check('google invalid token -> 401', googleBad.status === 401, googleBad);

  // ---------- Catalog ----------
  // Each run sells seeded items (multi-buy order, bundle): restock them so the test can be re-run.
  await prisma.product.updateMany({
    where: { sku: { startsWith: 'BM-DEMO-' }, stock: { lt: 2 }, status: { in: ['ACTIVE', 'SOLD_OUT'] } },
    data: { stock: 2, status: 'ACTIVE' },
  });
  const home = await call('GET', '/home', { token: customer });
  check('home feed', home.data.banners.length >= 3 && home.data.newArrivals.length > 0 && home.data.discountTiers.length === 3, home.data);
  const seededBundle = home.data.bundles.find((b) => b.title === 'Newborn starter pack');
  check('home bundle', seededBundle?.available > 0 && seededBundle.price < seededBundle.originalPrice, home.data.bundles);
  const search = await call('GET', '/products?q=dress&sort=price_asc');
  check('search', search.data.items.length >= 2 && search.data.items[0].price <= search.data.items[1].price, search.data);
  const byCat = await call('GET', '/products?category=women');
  check('category incl. children', byCat.data.total >= 4, byCat.data.total);
  const filtered = await call('GET', '/products?condition=NEW_WITH_TAGS&maxPrice=1000');
  check('filters', filtered.data.items.every((p) => p.condition === 'NEW_WITH_TAGS' && p.price <= 1000), filtered.data);
  const cats = (await call('GET', '/categories')).data;
  const catBySlug = (slug) => cats.find((c) => c.slug === slug);
  check(
    'size scale per category',
    catBySlug('women-dresses')?.sizes.includes('M') &&
      catBySlug('women-shoes')?.sizes.includes('39') &&
      catBySlug('kids-girls')?.sizes.includes('5Y') &&
      catBySlug('women-accessories')?.sizes.length === 0 &&
      catBySlug('women-dresses')?.parent?.slug === 'women' &&
      catBySlug('women-dresses')?.icon === 'dress',
    cats.map((c) => [c.slug, c.sizeType]),
  );
  const bySizes = await call('GET', '/products?size=M,L&color=blue,navy');
  check(
    'filter by several sizes and colours',
    bySizes.data.items.length > 0 && bySizes.data.items.every((p) => ['M', 'L'].includes(p.size) && ['blue', 'navy'].includes(p.color)),
    bySizes.data.items.map((p) => [p.size, p.color]),
  );
  const products = (await call('GET', '/products?pageSize=50&sort=price_asc')).data.items;
  const detail = await call('GET', `/products/${products[0].id}`);
  check('product detail', detail.data.id === products[0].id && Array.isArray(detail.data.related) && detail.data.images.length === 3, detail.data);
  const fav = await call('POST', `/me/favorites/${products[0].id}`, { token: customer });
  const favs = await call('GET', '/me/favorites', { token: customer });
  check('favorites', fav.status === 204 && favs.data.some((p) => p.id === products[0].id), favs);
  await call('DELETE', `/me/favorites/${products[0].id}`, { token: customer });

  // ---------- Quote & multi-buy ----------
  const zones = (await call('GET', '/zones')).data;
  const westlands = zones.find((z) => z.name === 'Westlands');
  const multi = products.filter((p) => p.stock >= 2).slice(0, 3);
  const quote = await call('POST', '/orders/quote', {
    body: { items: multi.map((p) => ({ productId: p.id, quantity: 1 })), zoneId: westlands.id },
  });
  const sub = multi.reduce((s, p) => s + p.price, 0);
  check('quote 3 items -> 10% off', quote.data.discountPercent === 10 && quote.data.discount === Math.round(sub * 0.1), quote.data);
  check('quote delivery fee', quote.data.deliveryFee === 250 && quote.data.total === sub - quote.data.discount + 250, quote.data);

  const address = { recipientName: 'Wanjiru Kamau', phone: '0722000111', street: 'Waiyaki Way, Westlands Square', landmark: 'Near Sarit' };

  // ---------- Order + mobile money (simulated) ----------
  const before = await Promise.all(multi.map((p) => stockOf(p.id)));
  const order = await call('POST', '/orders', {
    token: customer,
    body: { items: multi.map((p) => ({ productId: p.id, quantity: 1 })), zoneId: westlands.id, paymentMethod: 'MPESA', address, saveAddress: true },
  });
  check('create order', order.status === 201 && order.data.status === 'PENDING_PAYMENT' && /^\d{4}$/.test(order.data.deliveryCode), order);
  const after = await Promise.all(multi.map((p) => stockOf(p.id)));
  check('stock reserved', after.every((s, i) => s === before[i] - 1), { before, after });
  const addresses = await call('GET', '/auth/me/addresses', { token: customer });
  check('address saved', addresses.data.length >= 1, addresses.data);

  const badPhone = await call('POST', `/payments/orders/${order.data.id}`, { token: customer, body: { method: 'MPESA', phone: '123' } });
  check('mock payment accepts any phone (real M-Pesa validates)', badPhone.status === 201, badPhone);
  // Wait for that simulated payment to settle.
  let pay = badPhone.data;
  for (let i = 0; i < 10 && pay.status === 'PENDING'; i++) {
    await sleep(1000);
    pay = (await call('GET', `/payments/${pay.id}`, { token: customer })).data;
  }
  check('simulated payment succeeds', pay.status === 'SUCCESS' && pay.receipt, pay);
  const paid = await call('GET', `/orders/${order.data.id}`, { token: customer });
  check('order confirmed after payment', paid.data.status === 'CONFIRMED' && paid.data.paymentStatus === 'PAID' && !paid.data.expiresAt, paid.data);
  const payAgain = await call('POST', `/payments/orders/${order.data.id}`, { token: customer, body: { method: 'MPESA', phone: '0712345678' } });
  check('paid order cannot be paid twice', payAgain.status === 409, payAgain);
  const otherUserView = await call('GET', `/orders/${order.data.id}`, { token: reg.data.token });
  check("other customer cannot see the order", otherUserView.status === 404, otherUserView);

  // ---------- M-Pesa callback: user cancels the PIN prompt ----------
  const p2 = products.find((p) => p.stock >= 1 && !multi.includes(p));
  const order2 = await call('POST', '/orders', {
    token: customer,
    body: { items: [{ productId: p2.id, quantity: 1 }], zoneId: westlands.id, paymentMethod: 'MPESA', address },
  });
  const pay2 = await call('POST', `/payments/orders/${order2.data.id}`, { token: customer, body: { phone: '0712345678' } });
  const badCallback = await call('POST', '/payments/callbacks/mpesa/wrong-token', { body: {} });
  check('callback with wrong token -> 403', badCallback.status === 403, badCallback);
  // The callback URL (with its secret token) is shown in Admin > Payment methods.
  const mpesaCallbackPath = new URL((await call('GET', '/admin/settings/payments', { token: admin })).data.mpesa.callbackUrl).pathname.replace('/api', '');
  const cb = await call('POST', mpesaCallbackPath, {
    body: { Body: { stkCallback: { MerchantRequestID: 'x', CheckoutRequestID: pay2.data.providerRef, ResultCode: 1032, ResultDesc: 'Request cancelled by user' } } },
  });
  check('callback acknowledged', cb.status === 200 && cb.data.ResultCode === 0, cb);
  await sleep(5000); // the simulated success must be ignored now
  const pay2After = (await call('GET', `/payments/${pay2.data.id}`, { token: customer })).data;
  const order2After = (await call('GET', `/orders/${order2.data.id}`, { token: customer })).data;
  check('cancelled PIN -> payment failed (idempotent)', pay2After.status === 'FAILED' && order2After.paymentStatus === 'FAILED', { pay2After, order2After });

  // Customer cancels -> stock released
  const stockBeforeCancel = await stockOf(p2.id);
  const cancel = await call('POST', `/orders/${order2.data.id}/cancel`, { token: customer });
  check('customer cancels', cancel.data.status === 'CANCELLED', cancel);
  check('stock released on cancel', (await stockOf(p2.id)) === stockBeforeCancel + 1);
  const cancelAgain = await call('POST', `/orders/${order2.data.id}/cancel`, { token: customer });
  check('cannot cancel twice', cancelAgain.status === 409, cancelAgain);
  const moves = await prisma.stockMovement.findMany({ where: { orderId: order2.data.id } });
  check('ledger: SALE + RELEASE', moves.length === 2 && moves.some((m) => m.type === 'SALE') && moves.some((m) => m.type === 'RELEASE'), moves);

  // ---------- Expiry of unpaid orders ----------
  const p3 = products.find((p) => p.stock >= 1 && p.id !== p2.id && !multi.includes(p));
  const order3 = await call('POST', '/orders', {
    token: customer,
    body: { items: [{ productId: p3.id, quantity: 1 }], zoneId: westlands.id, paymentMethod: 'AIRTEL_MONEY', address },
  });
  const stockReserved = await stockOf(p3.id);
  await prisma.order.update({ where: { id: order3.data.id }, data: { expiresAt: new Date(Date.now() - 1000) } });
  const { expireUnpaidOrders } = await import('../dist/modules/orders/orders.service.js');
  await expireUnpaidOrders();
  const order3After = (await call('GET', `/orders/${order3.data.id}`, { token: customer })).data;
  check('unpaid order expires and releases stock', order3After.status === 'CANCELLED' && (await stockOf(p3.id)) === stockReserved + 1, order3After);

  // ---------- Last item: concurrent buyers ----------
  const last = await prisma.product.create({
    data: { sku: `E2E-${Date.now()}`, title: 'E2E last item', price: 500, stock: 1 },
  });
  const buyer2 = reg.data.token;
  const race = await Promise.all(
    [customer, buyer2].map((token) =>
      call('POST', '/orders', {
        token,
        body: { items: [{ productId: last.id, quantity: 1 }], zoneId: westlands.id, paymentMethod: 'CASH_ON_DELIVERY', address },
      }),
    ),
  );
  check('only one buyer gets the last item', race.filter((r) => r.status === 201).length === 1 && race.filter((r) => r.status === 409).length === 1, race.map((r) => r.status));
  const lastAfter = await prisma.product.findUnique({ where: { id: last.id } });
  check('last item sold out', lastAfter.stock === 0 && lastAfter.status === 'SOLD_OUT', lastAfter);

  // ---------- Bundle + cash on delivery ----------
  const bundle = seededBundle;
  const codOrder = await call('POST', '/orders', {
    token: customer,
    body: { bundles: [{ bundleId: bundle.id, quantity: 1 }], items: [], zoneId: westlands.id, paymentMethod: 'CASH_ON_DELIVERY', address },
  });
  check('bundle COD order', codOrder.status === 201 && codOrder.data.status === 'CONFIRMED' && codOrder.data.total === bundle.price + 250, codOrder);
  check('bundle not discounted twice', codOrder.data?.discount === 0, codOrder.data);
  const bundleMoves = await prisma.stockMovement.count({ where: { orderId: codOrder.data.id, type: 'SALE' } });
  check('bundle takes stock of each item', bundleMoves === bundle.items.length, bundleMoves);

  // ---------- Admin workflow ----------
  const forbidden = await call('GET', '/admin/stats', { token: customer });
  check('customer cannot open admin', forbidden.status === 403, forbidden);
  const supportOnStats = await call('GET', '/admin/stats', { token: support });
  check('support agent limited to support inbox', supportOnStats.status === 403, supportOnStats);
  const stats = await call('GET', '/admin/stats', { token: admin });
  check('admin stats', stats.status === 200 && stats.data.ordersToday >= 4 && stats.data.last7Days.length === 7, stats.data);

  const badJump = await call('PATCH', `/admin/orders/${codOrder.data.id}`, { token: admin, body: { status: 'DELIVERED' } });
  check('invalid status jump refused', badJump.status === 409, badJump);
  const prep = await call('PATCH', `/admin/orders/${codOrder.data.id}`, { token: admin, body: { status: 'PREPARING' } });
  const ready = await call('PATCH', `/admin/orders/${codOrder.data.id}`, { token: admin, body: { status: 'READY' } });
  check('admin moves order to READY', prep.data.status === 'PREPARING' && ready.data.status === 'READY', ready.data);
  const riderUser = await prisma.user.findUnique({ where: { email: 'rider@babymama.co.ke' } });
  const assign = await call('POST', `/admin/orders/${codOrder.data.id}/assign`, { token: admin, body: { driverId: riderUser.id } });
  check('assign rider', assign.data.delivery.status === 'ASSIGNED' && assign.data.delivery.driver.id === riderUser.id, assign.data);
  const searchOrders = await call('GET', `/admin/orders?q=${codOrder.data.number}`, { token: admin });
  check('admin search by order number', searchOrders.data.items.length === 1, searchOrders.data);

  // ---------- Rider app ----------
  const riderMe = await call('PATCH', '/driver/me', { token: rider, body: { isOnline: true } });
  check('rider goes online', riderMe.data.isOnline === true, riderMe);
  const loc = await call('POST', '/driver/location', { token: rider, body: { lat: -1.2649, lng: 36.8028 } });
  check('rider location', loc.status === 204, loc);
  const available = await call('GET', '/driver/deliveries?scope=available', { token: rider });
  check('paid MPESA order is available to riders', available.data.some((d) => d.order.id === order.data.id), available.data.map((d) => d.order.number));
  const active = await call('GET', '/driver/deliveries?scope=active', { token: rider });
  const delivery = active.data.find((d) => d.order.id === codOrder.data.id);
  check('assigned delivery listed', delivery && delivery.order.amountToCollect === codOrder.data.total && delivery.order.deliveryCode === null, delivery);
  const customerOnDriver = await call('GET', '/driver/deliveries', { token: customer });
  check('customer cannot use rider API', customerOnDriver.status === 403, customerOnDriver);

  const accept = await call('POST', `/driver/deliveries/${delivery.id}/accept`, { token: rider });
  check('accept', accept.data.status === 'ACCEPTED', accept);
  const early = await call('POST', `/driver/deliveries/${delivery.id}/status`, { token: rider, body: { status: 'PICKED_UP' } });
  check('picked up -> order out for delivery', early.data.status === 'PICKED_UP' && early.data.order.status === 'OUT_FOR_DELIVERY', early.data);
  await call('POST', `/driver/deliveries/${delivery.id}/status`, { token: rider, body: { status: 'IN_TRANSIT' } });
  await call('POST', '/driver/location', { token: rider, body: { lat: -1.2655, lng: 36.805 } });
  const tracking = (await call('GET', `/orders/${codOrder.data.id}`, { token: customer })).data;
  check('customer sees rider + position', tracking.delivery.driver.name === 'Kevin Otieno' && tracking.delivery.lastLat === -1.2655, tracking.delivery);
  const wrongCode = await call('POST', `/driver/deliveries/${delivery.id}/complete`, {
    token: rider,
    body: { code: codOrder.data.deliveryCode === '0000' ? '1111' : '0000' },
  });
  check('wrong delivery code refused', wrongCode.status === 400, wrongCode);
  const done = await call('POST', `/driver/deliveries/${delivery.id}/complete`, { token: rider, body: { code: codOrder.data.deliveryCode } });
  check('delivered with code', done.data.status === 'DELIVERED' && done.data.cashCollected === codOrder.data.total, done.data);
  const delivered = (await call('GET', `/orders/${codOrder.data.id}`, { token: customer })).data;
  check('COD order delivered and paid', delivered.status === 'DELIVERED' && delivered.paymentStatus === 'PAID', delivered);
  const riderStats = (await call('GET', '/driver/me', { token: rider })).data;
  check('rider stats', riderStats.stats.deliveredToday >= 1 && riderStats.stats.cashCollectedToday >= codOrder.data.total, riderStats.stats);

  // Second rider flow: take an available delivery, then report a failure
  const take = await call('POST', `/driver/deliveries/${available.data.find((d) => d.order.id === order.data.id).id}/accept`, { token: rider });
  const fail = await call('POST', `/driver/deliveries/${take.data.id}/fail`, { token: rider, body: { reason: 'Customer not reachable' } });
  check('rider reports failure -> order back to READY', fail.data.status === 'FAILED' && fail.data.order.status === 'READY', fail.data);

  // ---------- Review ----------
  const earlyReview = await call('POST', `/orders/${order.data.id}/review`, { token: customer, body: { rating: 5 } });
  check('cannot review before delivery', earlyReview.status === 409, earlyReview);
  const review = await call('POST', `/orders/${codOrder.data.id}/review`, {
    token: customer,
    body: { rating: 4, driverRating: 5, comment: 'Great quality, fast rider!' },
  });
  check('review', review.status === 201 && review.data.review.rating === 4, review);
  const review2 = await call('POST', `/orders/${codOrder.data.id}/review`, { token: customer, body: { rating: 1 } });
  check('only one review per order', review2.status === 409, review2);
  const reviews = await call('GET', '/admin/reviews', { token: admin });
  check('admin sees reviews', reviews.data.items.length >= 1 && reviews.data.averageRating >= 1, reviews.data);
  const drivers = await call('GET', '/admin/drivers', { token: admin });
  check('rider rating aggregated', drivers.data.find((d) => d.id === riderUser.id)?.rating === 5, drivers.data);

  // ---------- Support ----------
  const ticket = await call('POST', '/support', {
    token: customer,
    body: { subject: 'Size question', message: 'Is the dress true to size?', orderId: codOrder.data.id },
  });
  check('open ticket', ticket.status === 201 && ticket.data.orderNumber === codOrder.data.number, ticket);
  const staffReply = await call('POST', `/admin/support/${ticket.data.id}/messages`, { token: support, body: { body: 'Yes, it fits well.' } });
  check('support agent replies', staffReply.status === 201 && staffReply.data.status === 'PENDING', staffReply);
  const thread = (await call('GET', `/support/${ticket.data.id}`, { token: customer })).data;
  check('customer sees staff reply', thread.messages.length === 2 && thread.messages[1].isStaff, thread);
  const otherTicket = await call('GET', `/support/${ticket.data.id}`, { token: buyer2 });
  check("other customer cannot read the ticket", otherTicket.status === 404, otherTicket);
  const resolve = await call('PATCH', `/admin/support/${ticket.data.id}`, { token: admin, body: { status: 'RESOLVED' } });
  check('resolve ticket', resolve.data.status === 'RESOLVED', resolve);

  // ---------- Stock management ----------
  const target = products[1];
  const s0 = await stockOf(target.id);
  const restock = await call('POST', `/admin/products/${target.id}/stock`, { token: admin, body: { type: 'RESTOCK', quantity: 5, reason: 'New bale' } });
  const correction = await call('POST', `/admin/products/${target.id}/stock`, { token: admin, body: { type: 'ADJUSTMENT', quantity: -2, reason: 'Damaged' } });
  check('restock + correction', restock.data.stock === s0 + 5 && correction.data.stock === s0 + 3, { s0, restock: restock.data.stock, correction: correction.data.stock });
  const tooMuch = await call('POST', `/admin/products/${target.id}/stock`, { token: admin, body: { type: 'ADJUSTMENT', quantity: -1000 } });
  check('stock cannot go negative', tooMuch.status === 409, tooMuch);
  const negativeRestock = await call('POST', `/admin/products/${target.id}/stock`, { token: admin, body: { type: 'RESTOCK', quantity: -1 } });
  check('restock must be positive', negativeRestock.status === 400, negativeRestock);
  const ledger = await call('GET', `/admin/stock/movements?productId=${target.id}`, { token: admin });
  check('movement ledger', ledger.data.items.length >= 3 && ledger.data.items[0].type === 'ADJUSTMENT', ledger.data.items.map((m) => m.type));
  const summary = await call('GET', '/admin/stock/summary', { token: admin });
  check('stock summary', summary.data.totalUnits > 0 && summary.data.stockValue > 0, summary.data);
  const low = await call('GET', '/admin/products?lowStock=true', { token: admin });
  check('low stock list', low.data.items.every((p) => p.stock <= p.lowStockThreshold), low.data.items.map((p) => [p.stock, p.lowStockThreshold]));

  // ---------- Payment settings (admin, no redeploy) ----------
  const settingsPath = '/admin/settings/payments';
  check('customer cannot read payment settings', (await call('GET', settingsPath, { token: customer })).status === 403);
  const savedKeys = await call('PUT', settingsPath, {
    token: admin,
    body: { mpesa: { enabled: true, consumerKey: 'e2e-key', consumerSecret: 'e2e-very-secret', shortcode: '174379', passkey: 'e2e-passkey' } },
  });
  const storedRow = await prisma.setting.findUnique({ where: { key: 'payments' } });
  check(
    'M-Pesa keys saved, secrets hidden and encrypted',
    savedKeys.status === 200 &&
      savedKeys.data.mpesa.ready &&
      savedKeys.data.mpesa.consumerSecretSet &&
      !JSON.stringify(savedKeys.data).includes('e2e-very-secret') &&
      !storedRow.value.includes('e2e-very-secret'),
    savedKeys.data,
  );
  const realMpesa = (await call('GET', '/payments/methods')).data.find((m) => m.method === 'MPESA');
  check('configured M-Pesa is no longer simulated', realMpesa && !realMpesa.simulated, realMpesa);
  await call('PUT', settingsPath, { token: admin, body: { cashOnDelivery: false, mpesa: { consumerKey: '', consumerSecret: '', shortcode: '', passkey: '' } } });
  const methodsNoCod = (await call('GET', '/payments/methods')).data;
  check(
    'cash on delivery switched off from the admin',
    !methodsNoCod.some((m) => m.method === 'CASH_ON_DELIVERY') && methodsNoCod.find((m) => m.method === 'MPESA')?.simulated,
    methodsNoCod,
  );
  await call('PUT', settingsPath, { token: admin, body: { cashOnDelivery: true } });

  // ---------- Categories (admin) ----------
  const newCat = await call('POST', '/admin/categories', {
    token: admin,
    body: { slug: `men-e2e-${Date.now()}`, nameEn: 'Swimwear', nameFr: 'Maillots', parentId: catBySlug('men').id, icon: 'tshirt' },
  });
  check('admin adds a sub-category', newCat.status === 201 && newCat.data.icon === 'tshirt' && newCat.data.sizes.includes('M'), newCat);
  const fullCat = await call('DELETE', `/admin/categories/${catBySlug('women-dresses').id}`, { token: admin });
  check('category with products cannot be deleted', fullCat.status === 409, fullCat);
  const delCat = await call('DELETE', `/admin/categories/${newCat.data.id}`, { token: admin });
  check('empty category deleted', delCat.status === 204, delCat);

  // ---------- Products (admin) ----------
  const menShirts = catBySlug('men-shirts').id;
  const shoeSizeOnShirt = await call('POST', '/admin/products', {
    token: admin,
    lang: 'fr',
    body: { title: 'Kitenge shirt', price: 900, stock: 2, categoryId: menShirts, size: '42' },
  });
  check('size outside the category scale refused', shoeSizeOnShirt.status === 400 && shoeSizeOnShirt.data.message.includes('taille'), shoeSizeOnShirt);
  const created = await call('POST', '/admin/products', {
    token: admin,
    body: {
      title: 'Kitenge shirt',
      price: 900,
      stock: 2,
      condition: 'VERY_GOOD',
      images: ['https://picsum.photos/seed/e2e/600/800'],
      categoryId: menShirts,
      size: 'L',
      color: 'multicolor',
    },
  });
  const toShoes = await call('PATCH', `/admin/products/${created.data.id}`, { token: admin, body: { categoryId: catBySlug('men-shoes').id } });
  check('moving to shoes needs a shoe size', toShoes.status === 400, toShoes);
  check('admin creates product', created.status === 201 && created.data.stock === 2 && created.data.sku.startsWith('BM-'), created);
  const edited = await call('PATCH', `/admin/products/${created.data.id}`, { token: admin, body: { price: 850, isFeatured: true } });
  check('admin edits product', edited.data.price === 850 && edited.data.isFeatured, edited.data);
  await call('DELETE', `/admin/products/${created.data.id}`, { token: admin });
  const archived = await call('GET', `/products/${created.data.id}`);
  check('archived product hidden from shop', archived.status === 404, archived);

  // ---------- Single seller: customer self-listing is not exposed ----------
  const listing = await call('POST', '/me/listings', {
    token: customer,
    body: { title: 'My denim skirt', condition: 'GOOD', price: 600, images: ['https://picsum.photos/seed/e2e2/600/800'] },
  });
  check('customer listing endpoint removed -> 404', listing.status === 404, listing);

  // ---------- Marketing ----------
  const banner = await call('POST', '/admin/banners', {
    token: admin,
    body: { titleEn: 'Back to school', titleFr: 'Rentrée', imageUrl: 'https://picsum.photos/seed/e2e3/1200/600', type: 'PRODUCT', targetId: products[0].id },
  });
  check('create banner', banner.status === 201, banner);
  const expired = await call('POST', '/admin/banners', {
    token: admin,
    body: { titleEn: 'Old', titleFr: 'Ancien', imageUrl: 'https://picsum.photos/seed/e2e4/1200/600', endsAt: '2020-01-01T00:00:00Z' },
  });
  const home2 = (await call('GET', '/home')).data;
  check('carousel shows active banners only', home2.banners.some((b) => b.id === banner.data.id) && !home2.banners.some((b) => b.id === expired.data.id));
  // Leave the carousel as seeded for the next run and for manual testing.
  await call('DELETE', `/admin/banners/${banner.data.id}`, { token: admin });
  await call('DELETE', `/admin/banners/${expired.data.id}`, { token: admin });
  const bundleItems = products.slice(4, 6).map((p) => ({ productId: p.id, quantity: 1 }));
  const itemsValue = products.slice(4, 6).reduce((s, p) => s + p.price, 0);
  const tooExpensive = await call('POST', '/admin/bundles', {
    token: admin,
    lang: 'fr',
    body: { title: 'Weekend look', price: itemsValue, items: bundleItems },
  });
  check('bundle priced >= its items is refused', tooExpensive.status === 400 && tooExpensive.data.error === 'bundle_price_too_high', tooExpensive);
  const newBundle = await call('POST', '/admin/bundles', {
    token: admin,
    body: { title: 'Weekend look', titleFr: 'Look du week-end', price: Math.round(itemsValue * 0.8), items: bundleItems },
  });
  check('create bundle', newBundle.status === 201 && newBundle.data.originalPrice === itemsValue && newBundle.data.items.length === 2, newBundle);
  const raise = await call('PATCH', `/admin/bundles/${newBundle.data.id}`, { token: admin, body: { price: itemsValue + 100 } });
  check('bundle price raise above items value refused', raise.status === 400, raise);
  await call('DELETE', `/admin/bundles/${newBundle.data.id}`, { token: admin });
  const tiers = await call('PUT', '/admin/discount-tiers', {
    token: admin,
    body: [
      { minItems: 2, percent: 5 },
      { minItems: 3, percent: 10 },
      { minItems: 5, percent: 15 },
    ],
  });
  check('update discount tiers', tiers.data.length === 3, tiers);
  const zone = await call('POST', '/admin/zones', { token: admin, body: { name: `Test zone ${Date.now()}`, fee: 600 } });
  check('create zone', zone.status === 201 && zone.data.fee === 600, zone);
  const staff = await call('POST', '/admin/staff', {
    token: admin,
    body: { name: 'New Rider', email: `rider${Date.now()}@babymama.co.ke`, password: 'Rider12345', role: 'DRIVER', plateNumber: 'KMEE 999Z' },
  });
  check('admin creates rider', staff.status === 201 && staff.data.role === 'DRIVER', staff);
  const woo = await call('GET', '/admin/woocommerce/status', { token: admin });
  check('woocommerce status', woo.status === 200 && woo.data.enabled === false, woo.data);
  const wooImport = await call('POST', '/admin/woocommerce/import', { token: admin, lang: 'fr' });
  check('woo import without config -> clear error', wooImport.status === 400 && wooImport.data.error === 'woocommerce_not_configured', wooImport);

  // ---------- Uploads ----------
  const png = Buffer.from(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    'base64',
  );
  const form = new FormData();
  form.append('file', new Blob([png], { type: 'image/png' }), 'pixel.png');
  const up = await fetch(`${API}/uploads`, { method: 'POST', headers: { Authorization: `Bearer ${admin}` }, body: form });
  const upData = await up.json();
  check('admin upload image', up.status === 201 && upData.url.includes('/uploads/'), upData);
  const served = await fetch(upData.url);
  check('uploaded image served', served.status === 200, served.status);
  const formTxt = new FormData();
  formTxt.append('file', new Blob(['hello'], { type: 'text/plain' }), 'notes.txt');
  const upBad = await fetch(`${API}/uploads`, { method: 'POST', headers: { Authorization: `Bearer ${admin}` }, body: formTxt });
  check('non-image upload refused', upBad.status === 400, upBad.status);
  const formCust = new FormData();
  formCust.append('file', new Blob([png], { type: 'image/png' }), 'pixel.png');
  const upCust = await fetch(`${API}/uploads`, { method: 'POST', headers: { Authorization: `Bearer ${customer}` }, body: formCust });
  check('customer cannot upload -> 403', upCust.status === 403, upCust.status);

  // ---------- Sign in by phone (SMS one-time code, simulated in dev) ----------
  const otpPhone = '0733444555';
  const otpReq = await call('POST', '/auth/phone/request', { body: { phone: otpPhone } });
  check('phone code sent (dev returns code)', otpReq.status === 200 && /^\d{6}$/.test(otpReq.data.devCode ?? ''), otpReq);
  const otpWrong = await call('POST', '/auth/phone/verify', { body: { phone: otpPhone, code: '000000' } });
  check('wrong code refused', otpWrong.status === 400, otpWrong);
  const otpOk = await call('POST', '/auth/phone/verify', { body: { phone: otpPhone, code: otpReq.data.devCode, name: 'Phone User' } });
  check('phone sign-in returns token + user', otpOk.status === 200 && otpOk.data.token && otpOk.data.user.id, otpOk);
  const phoneMe = await call('GET', '/auth/me', { token: otpOk.data.token });
  check('phone account usable', phoneMe.status === 200 && phoneMe.data.role === 'CUSTOMER', phoneMe);
  const otpBadPhone = await call('POST', '/auth/phone/request', { body: { phone: '123' }, lang: 'fr' });
  check('invalid phone refused', otpBadPhone.status === 400, otpBadPhone);
  await prisma.user.deleteMany({ where: { email: `phone+254733444555@babymama.local` } });
}

main()
  .catch((e) => failures.push(`CRASH: ${e.stack ?? e}`))
  .finally(async () => {
    await prisma.$disconnect();
    console.log(`\n${passed} passed, ${failures.length} failed`);
    for (const f of failures) console.log(`  FAIL ${f}`);
    process.exit(failures.length ? 1 : 0);
  });
