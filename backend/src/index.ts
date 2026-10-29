import { createApp } from './app';
import { config } from './config';
import { prisma } from './lib/prisma';
import { expireUnpaidOrders } from './modules/orders/orders.service';

const app = createApp();

const server = app.listen(config.port, () => {
  console.log(`Babymama API listening on ${config.publicUrl} (port ${config.port})`);
});

// Release stock held by unpaid orders.
const timer = setInterval(() => {
  expireUnpaidOrders().catch((e) => console.error('[jobs] expireUnpaidOrders', e));
}, 60_000);

async function shutdown() {
  clearInterval(timer);
  server.close();
  await prisma.$disconnect();
  process.exit(0);
}
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
