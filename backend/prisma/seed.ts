import bcrypt from 'bcryptjs';
import { PrismaClient, type ProductCondition, type SizeType } from '@prisma/client';

const prisma = new PrismaClient();

const zones: [string, number, number][] = [
  ['CBD', 150, 60],
  ['Westlands', 250, 75],
  ['Parklands', 250, 75],
  ['Kilimani', 250, 75],
  ['Kileleshwa', 250, 75],
  ['Lavington', 300, 90],
  ['Upper Hill', 250, 75],
  ['South B / South C', 250, 90],
  ['Eastleigh', 200, 75],
  ['Langata', 350, 100],
  ['Karen', 450, 120],
  ['Embakasi', 350, 120],
  ['Kasarani', 350, 120],
  ['Roysambu / TRM', 300, 100],
  ['Ruaka', 400, 120],
  ['Rongai', 450, 150],
  ['Kitengela', 500, 150],
  ['Thika Road (Juja)', 550, 180],
];

// Three departments (Women | Men | Kids). Each sub-category inherits its department's size scale
// unless it sets its own: shoes use EU numbers, accessories have no size.
// Icons are keys drawn by the apps (packages/babymama_core/lib/src/category_icons.dart).
const categories: { slug: string; en: string; fr: string; icon: string; parent?: string; sizeType?: SizeType }[] = [
  { slug: 'women', en: 'Women', fr: 'Femmes', icon: 'women', sizeType: 'CLOTHING' },
  { slug: 'men', en: 'Men', fr: 'Hommes', icon: 'men', sizeType: 'CLOTHING' },
  { slug: 'kids', en: 'Kids', fr: 'Enfants', icon: 'kids', sizeType: 'KIDS_AGE' },
  { slug: 'women-dresses', en: 'Dresses', fr: 'Robes', icon: 'dress', parent: 'women' },
  { slug: 'women-tops', en: 'Tops & blouses', fr: 'Hauts & chemisiers', icon: 'tshirt', parent: 'women' },
  { slug: 'women-knitwear', en: 'Jumpers & cardigans', fr: 'Pulls & gilets', icon: 'sweater', parent: 'women' },
  { slug: 'women-trousers', en: 'Jeans & trousers', fr: 'Jeans & pantalons', icon: 'trousers', parent: 'women' },
  { slug: 'women-skirts', en: 'Skirts', fr: 'Jupes', icon: 'skirt', parent: 'women' },
  { slug: 'women-coats', en: 'Coats & jackets', fr: 'Manteaux & vestes', icon: 'coat', parent: 'women' },
  { slug: 'women-sport', en: 'Sportswear', fr: 'Tenues de sport', icon: 'sport', parent: 'women' },
  { slug: 'women-traditional', en: 'African prints', fr: 'Pagnes & kitenge', icon: 'pattern', parent: 'women' },
  { slug: 'women-maternity', en: 'Maternity', fr: 'Maternité', icon: 'maternity', parent: 'women' },
  { slug: 'women-shoes', en: 'Shoes', fr: 'Chaussures', icon: 'heel', parent: 'women', sizeType: 'SHOES' },
  { slug: 'women-bags', en: 'Bags', fr: 'Sacs', icon: 'bag', parent: 'women', sizeType: 'ONE_SIZE' },
  { slug: 'women-accessories', en: 'Jewellery & accessories', fr: 'Bijoux & accessoires', icon: 'jewel', parent: 'women', sizeType: 'ONE_SIZE' },
  { slug: 'men-tshirts', en: 'T-shirts & polos', fr: 'T-shirts & polos', icon: 'tshirt', parent: 'men' },
  { slug: 'men-shirts', en: 'Shirts', fr: 'Chemises', icon: 'shirt', parent: 'men' },
  { slug: 'men-knitwear', en: 'Jumpers & hoodies', fr: 'Pulls & sweats', icon: 'sweater', parent: 'men' },
  { slug: 'men-trousers', en: 'Jeans & trousers', fr: 'Jeans & pantalons', icon: 'trousers', parent: 'men' },
  { slug: 'men-shorts', en: 'Shorts', fr: 'Shorts', icon: 'shorts', parent: 'men' },
  { slug: 'men-coats', en: 'Coats & jackets', fr: 'Manteaux & vestes', icon: 'coat', parent: 'men' },
  { slug: 'men-suits', en: 'Suits & blazers', fr: 'Costumes & blazers', icon: 'tie', parent: 'men' },
  { slug: 'men-sport', en: 'Sportswear', fr: 'Tenues de sport', icon: 'sport', parent: 'men' },
  { slug: 'men-shoes', en: 'Shoes', fr: 'Chaussures', icon: 'shoe', parent: 'men', sizeType: 'SHOES' },
  { slug: 'men-accessories', en: 'Caps & accessories', fr: 'Casquettes & accessoires', icon: 'cap', parent: 'men', sizeType: 'ONE_SIZE' },
  { slug: 'kids-baby', en: 'Baby (0-24 months)', fr: 'Bébé (0-24 mois)', icon: 'bodysuit', parent: 'kids' },
  { slug: 'kids-girls', en: 'Girls', fr: 'Filles', icon: 'dress', parent: 'kids' },
  { slug: 'kids-boys', en: 'Boys', fr: 'Garçons', icon: 'tshirt', parent: 'kids' },
  { slug: 'kids-pyjamas', en: 'Pyjamas', fr: 'Pyjamas', icon: 'moon', parent: 'kids' },
  { slug: 'kids-school', en: 'School uniforms', fr: 'Uniformes scolaires', icon: 'school', parent: 'kids' },
  { slug: 'kids-coats', en: 'Coats & jackets', fr: 'Manteaux & vestes', icon: 'coat', parent: 'kids' },
  { slug: 'kids-shoes', en: 'Shoes', fr: 'Chaussures', icon: 'sneaker', parent: 'kids', sizeType: 'SHOES' },
  { slug: 'kids-accessories', en: 'Hats & accessories', fr: 'Bonnets & accessoires', icon: 'hat', parent: 'kids', sizeType: 'ONE_SIZE' },
];

type SeedProduct = {
  title: string;
  cat: string;
  price: number;
  was?: number;
  size?: string;
  color: string;
  brand?: string;
  condition: ProductCondition;
  stock: number;
};

const products: SeedProduct[] = [
  { title: 'Floral maxi dress', cat: 'women-dresses', price: 1200, was: 1800, size: 'M', color: 'multicolor', brand: 'Zara', condition: 'VERY_GOOD', stock: 1 },
  { title: 'Ankara wrap dress', cat: 'women-dresses', price: 1500, size: 'L', color: 'orange', condition: 'NEW_WITH_TAGS', stock: 2 },
  { title: 'White linen blouse', cat: 'women-tops', price: 650, size: 'S', color: 'white', brand: 'H&M', condition: 'GOOD', stock: 3 },
  { title: 'Mom jeans high waist', cat: 'women-trousers', price: 900, size: 'M', color: 'blue', brand: "Levi's", condition: 'VERY_GOOD', stock: 2 },
  { title: 'Pleated midi skirt', cat: 'women-skirts', price: 750, size: 'S', color: 'beige', brand: 'Mango', condition: 'VERY_GOOD', stock: 1 },
  { title: 'Wool blend coat', cat: 'women-coats', price: 2400, was: 3200, size: 'M', color: 'brown', condition: 'GOOD', stock: 1 },
  { title: 'Maternity jumpsuit', cat: 'women-dresses', price: 1300, size: 'M', color: 'black', brand: 'ASOS', condition: 'VERY_GOOD', stock: 1 },
  { title: 'Leather ankle boots', cat: 'women-shoes', price: 1600, size: '39', color: 'black', condition: 'GOOD', stock: 1 },
  { title: 'Leather crossbody bag', cat: 'women-accessories', price: 1400, color: 'brown', brand: 'Mango', condition: 'VERY_GOOD', stock: 1 },
  { title: 'Straw summer hat', cat: 'women-accessories', price: 350, color: 'beige', condition: 'VERY_GOOD', stock: 3 },
  { title: 'Vintage denim jacket', cat: 'men-coats', price: 1800, was: 2500, size: 'L', color: 'blue', brand: "Levi's", condition: 'GOOD', stock: 1 },
  { title: 'Puffer jacket', cat: 'men-coats', price: 2200, size: 'M', color: 'navy', brand: 'The North Face', condition: 'VERY_GOOD', stock: 1 },
  { title: 'Checked flannel shirt', cat: 'men-shirts', price: 700, size: 'XL', color: 'red', condition: 'GOOD', stock: 4 },
  { title: 'Plain cotton polo', cat: 'men-tshirts', price: 450, size: 'L', color: 'green', brand: 'Ralph Lauren', condition: 'VERY_GOOD', stock: 2 },
  { title: 'Chino trousers', cat: 'men-trousers', price: 850, size: 'M', color: 'beige', brand: 'Gap', condition: 'GOOD', stock: 2 },
  { title: 'Canvas sneakers', cat: 'men-shoes', price: 1100, size: '43', color: 'white', brand: 'Converse', condition: 'GOOD', stock: 1 },
  { title: 'Girls tutu party dress', cat: 'kids-girls', price: 550, size: '5Y', color: 'pink', condition: 'NEW_WITHOUT_TAGS', stock: 3 },
  { title: 'Boys dungarees', cat: 'kids-boys', price: 500, size: '3Y', color: 'blue', brand: 'Next', condition: 'GOOD', stock: 2 },
  { title: 'Baby bodysuits (pack of 3)', cat: 'kids-baby', price: 600, size: '0-3M', color: 'white', brand: "Carter's", condition: 'NEW_WITH_TAGS', stock: 5 },
  { title: 'Knitted baby cardigan', cat: 'kids-baby', price: 450, size: '6-12M', color: 'yellow', condition: 'VERY_GOOD', stock: 2 },
  { title: 'Kids sneakers', cat: 'kids-shoes', price: 800, size: '28', color: 'grey', brand: 'Nike', condition: 'GOOD', stock: 2 },
];

const img = (seed: string, n = 0) => `https://picsum.photos/seed/babymama-${seed}-${n}/600/800`;

/** Support, rider and customer demo accounts share SEED_DEMO_PASSWORD when set (use one for any public deployment). */
const demoPassword = (localDefault: string) => process.env.SEED_DEMO_PASSWORD || localDefault;

async function main() {
  const adminEmail = process.env.SEED_ADMIN_EMAIL ?? 'admin@babymama.co.ke';
  const adminPassword = process.env.SEED_ADMIN_PASSWORD ?? 'ChangeMe123!';

  await prisma.user.upsert({
    where: { email: adminEmail },
    update: {},
    create: { email: adminEmail, name: 'Babymama Admin', role: 'ADMIN', passwordHash: await bcrypt.hash(adminPassword, 10) },
  });
  await prisma.user.upsert({
    where: { email: 'support@babymama.co.ke' },
    update: {},
    create: { email: 'support@babymama.co.ke', name: 'Support Team', role: 'SUPPORT', passwordHash: await bcrypt.hash(demoPassword('Support123!'), 10) },
  });
  await prisma.user.upsert({
    where: { email: 'rider@babymama.co.ke' },
    update: {},
    create: {
      email: 'rider@babymama.co.ke',
      name: 'Kevin Otieno',
      phone: '0712345678',
      role: 'DRIVER',
      passwordHash: await bcrypt.hash(demoPassword('Rider123!'), 10),
      driverProfile: { create: { vehicleType: 'MOTORBIKE', plateNumber: 'KMDA 123A' } },
    },
  });
  await prisma.user.upsert({
    where: { email: 'customer@babymama.co.ke' },
    update: {},
    create: { email: 'customer@babymama.co.ke', name: 'Wanjiru Kamau', phone: '0722000111', passwordHash: await bcrypt.hash(demoPassword('Customer123!'), 10) },
  });

  for (const [i, [name, fee, etaMinutes]] of zones.entries()) {
    await prisma.deliveryZone.upsert({ where: { name }, update: {}, create: { name, fee, etaMinutes, position: i } });
  }

  const catIds = new Map<string, string>();
  for (const [i, c] of categories.entries()) {
    const cat = await prisma.category.upsert({
      where: { slug: c.slug },
      update: {},
      create: {
        slug: c.slug,
        nameEn: c.en,
        nameFr: c.fr,
        position: i,
        icon: c.icon,
        sizeType: c.sizeType,
        parentId: c.parent ? catIds.get(c.parent) : undefined,
      },
    });
    catIds.set(c.slug, cat.id);
  }

  for (const [minItems, percent] of [
    [2, 5],
    [3, 10],
    [5, 15],
  ]) {
    await prisma.discountTier.upsert({ where: { minItems }, update: {}, create: { minItems, percent } });
  }

  if ((await prisma.product.count()) === 0) {
    for (const [i, p] of products.entries()) {
      await prisma.product.create({
        data: {
          sku: `BM-DEMO-${String(i + 1).padStart(3, '0')}`,
          title: p.title,
          description: `${p.title} in ${p.condition.toLowerCase().replace(/_/g, ' ')} condition. Carefully selected, cleaned and checked by the Babymama team in Nairobi.`,
          price: p.price,
          compareAtPrice: p.was,
          size: p.size,
          color: p.color,
          brand: p.brand,
          condition: p.condition,
          stock: p.stock,
          isFeatured: i % 3 === 0,
          categoryId: catIds.get(p.cat),
          images: { create: [0, 1, 2].map((n) => ({ url: img(String(i), n), position: n })) },
          movements: { create: { type: 'RESTOCK', quantity: p.stock, stockAfter: p.stock, reason: 'Seed' } },
        },
      });
    }
  }

  if ((await prisma.banner.count()) === 0) {
    await prisma.banner.createMany({
      data: [
        {
          titleEn: 'New arrivals every Friday',
          titleFr: 'Nouveautés chaque vendredi',
          subtitleEn: 'Hand-picked pre-loved fashion for the whole family',
          subtitleFr: 'Mode de seconde main sélectionnée pour toute la famille',
          imageUrl: 'https://picsum.photos/seed/babymama-banner-1/1200/600',
          type: 'NEW_ARRIVALS',
          position: 0,
        },
        {
          titleEn: 'Buy 3, save 10%',
          titleFr: 'Achetez 3, économisez 10 %',
          subtitleEn: 'Bundle your favourites and pay less',
          subtitleFr: 'Regroupez vos coups de cœur et payez moins',
          imageUrl: 'https://picsum.photos/seed/babymama-banner-2/1200/600',
          type: 'PROMO',
          position: 1,
        },
        {
          titleEn: 'Baby essentials',
          titleFr: 'Essentiels bébé',
          subtitleEn: 'Bodysuits, cardigans and more from KSh 400',
          subtitleFr: 'Bodies, gilets et plus dès 400 KSh',
          imageUrl: 'https://picsum.photos/seed/babymama-banner-3/1200/600',
          type: 'CATEGORY',
          targetId: catIds.get('kids-baby'),
          position: 2,
        },
      ],
    });
  }

  if ((await prisma.bundle.count()) === 0) {
    const babyItems = await prisma.product.findMany({ where: { categoryId: catIds.get('kids-baby') } });
    if (babyItems.length >= 2) {
      await prisma.bundle.create({
        data: {
          title: 'Newborn starter pack',
          titleFr: 'Kit naissance',
          description: 'Everything a newborn needs for the first weeks.',
          price: Math.round(babyItems.reduce((s, p) => s + p.price, 0) * 0.8),
          items: { create: babyItems.map((p) => ({ productId: p.id, quantity: 1 })) },
        },
      });
    }
  }

  console.log('Seed done.');
  console.log(`  Admin:    ${adminEmail} / ${adminPassword}`);
  console.log(`  Support:  support@babymama.co.ke / ${demoPassword('Support123!')}`);
  console.log(`  Rider:    rider@babymama.co.ke / ${demoPassword('Rider123!')}`);
  console.log(`  Customer: customer@babymama.co.ke / ${demoPassword('Customer123!')}`);
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
