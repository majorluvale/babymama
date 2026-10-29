import 'dart:math' as math;

import 'package:babymama_core/babymama_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../screens/auth_screen.dart';
import '../screens/bundle_screen.dart';
import '../screens/cart_screen.dart';
import '../screens/catalog_screen.dart';
import '../screens/product_screen.dart';
import '../state/cart.dart';
import '../state/favorites.dart';
import 'site_layout.dart';

// ---------- Navigation helpers ----------

/// Opens the sign-in screen when needed. Returns true when the user is signed in.
Future<bool> ensureLoggedIn(BuildContext context) async {
  if (context.read<Session>().isLoggedIn) return true;
  final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const AuthScreen()));
  return ok == true;
}

void openProduct(BuildContext context, String id) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductScreen(productId: id)));

void openBundle(BuildContext context, String id) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => BundleScreen(bundleId: id)));

void openCatalog(BuildContext context, {String? categoryId, String? query, String sort = 'newest', String? title}) =>
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CatalogScreen(categoryId: categoryId, initialQuery: query, initialSort: sort, title: title),
    ));

void openCart(BuildContext context) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CartScreen()));

Future<void> openExternal(String url) async {
  final uri = Uri.tryParse(url);
  if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
}

void openBanner(BuildContext context, BannerSlide b) {
  switch (b.type) {
    case 'PRODUCT':
      if (b.targetId != null) openProduct(context, b.targetId!);
    case 'CATEGORY':
      openCatalog(context, categoryId: b.targetId, title: b.title(context.lang));
    case 'BUNDLE':
      if (b.targetId != null) openBundle(context, b.targetId!);
    case 'NEW_ARRIVALS':
      openCatalog(context, sort: 'newest', title: context.tr('new_arrivals'));
    default:
      if (b.url != null) openExternal(b.url!);
  }
}

Future<void> toggleFavorite(BuildContext context, String productId) async {
  if (!await ensureLoggedIn(context)) return;
  if (!context.mounted) return;
  try {
    await context.read<FavoritesController>().toggle(productId);
  } on ApiException catch (e) {
    if (context.mounted) showSnack(context, e.message, error: true);
  }
}

void addProductToCart(BuildContext context, Product p) {
  final added = context.read<CartController>().addProduct(p);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(added ? context.tr('added_to_cart') : context.tr('max_stock_reached')),
      action: SnackBarAction(label: context.tr('view_cart'), onPressed: () => openCart(context)),
    ));
}

// ---------- Widgets ----------

class ShopProductCard extends StatelessWidget {
  const ShopProductCard({super.key, required this.product, this.width});

  final Product product;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final favorites = context.watch<FavoritesController>();
    return ProductCard(
      product: product,
      width: width,
      favorite: favorites.isFavorite(product.id),
      onTap: () => openProduct(context, product.id),
      onFavorite: () => toggleFavorite(context, product.id),
    );
  }
}

/// Product grid as a sliver: fixed columns (2 on phones up to 4 on the website) so every card lines up.
/// [gutter] is the side padding; by default the content is centred at [kSiteMaxWidth].
class ProductSliverGrid extends StatelessWidget {
  const ProductSliverGrid({super.key, required this.products, this.gutter, this.maxColumns = 4});

  final List<Product> products;
  final double? gutter;
  final int maxColumns;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(builder: (context, constraints) {
      final width = constraints.crossAxisExtent;
      final side = gutter ?? siteGutter(width);
      final inner = width - side * 2;
      final columns = math.min(maxColumns, gridColumns(inner));
      final spacing = inner >= 600 ? 24.0 : 12.0;
      final tileWidth = (inner - spacing * (columns - 1)) / columns;
      return SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: side),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing,
            mainAxisSpacing: 28,
            mainAxisExtent: tileWidth * 4 / 3 + kProductCardInfoHeight,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) => ShopProductCard(product: products[i]),
            childCount: products.length,
          ),
        ),
      );
    });
  }
}

/// One row of products: a scrolling strip on phones, the first 4 side by side on larger screens.
class ProductStrip extends StatelessWidget {
  const ProductStrip({super.key, required this.products});

  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth >= 600) {
        const columns = 4;
        const spacing = 24.0;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < columns; i++) ...[
              if (i > 0) const SizedBox(width: spacing),
              Expanded(child: i < products.length ? ShopProductCard(product: products[i]) : const SizedBox.shrink()),
            ],
          ],
        );
      }
      const cardWidth = 150.0;
      return SizedBox(
        height: cardWidth * 4 / 3 + kProductCardInfoHeight,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: products.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, i) => ShopProductCard(product: products[i], width: cardWidth),
        ),
      );
    });
  }
}

class CartButton extends StatelessWidget {
  const CartButton({super.key});

  @override
  Widget build(BuildContext context) {
    final count = context.watch<CartController>().count;
    return IconButton(
      tooltip: context.tr('cart'),
      onPressed: () => openCart(context),
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        child: const Icon(Icons.shopping_bag_outlined),
      ),
    );
  }
}

class BundleCard extends StatelessWidget {
  const BundleCard({super.key, required this.bundle, this.width = 260});

  final Bundle bundle;
  final double width;

  @override
  Widget build(BuildContext context) {
    final b = bundle;
    return SizedBox(
      width: width,
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        color: BmColors.surface,
        child: InkWell(
          onTap: () => openBundle(context, b.id),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    BmImage(b.imageUrl),
                    if (b.savingPercent > 0)
                      Positioned(
                        left: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: BmColors.danger, borderRadius: BorderRadius.circular(4)),
                          child: Text('-${b.savingPercent}%',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(b.localizedTitle(context.lang),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Row(children: [
                      Text(formatKes(b.price), style: const TextStyle(fontWeight: FontWeight.w700, color: BmColors.primary)),
                      const SizedBox(width: 6),
                      Text(formatKes(b.originalPrice),
                          style: const TextStyle(color: BmColors.muted, fontSize: 12, decoration: TextDecoration.lineThrough)),
                    ]),
                    Text(context.tr('bundle_items', {'n': b.items.length}),
                        style: const TextStyle(color: BmColors.muted, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Buy 2: -5% · Buy 3: -10%" banner explaining multi-buy discounts.
class DiscountTiersBanner extends StatelessWidget {
  const DiscountTiersBanner({super.key, required this.tiers});

  final List<DiscountTier> tiers;

  @override
  Widget build(BuildContext context) {
    if (tiers.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: BmColors.surface, borderRadius: BorderRadius.circular(6)),
      child: Row(
        children: [
          const Icon(Icons.local_offer_outlined, color: BmColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr('multibuy_title'), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  tiers.map((t) => context.tr('multibuy_tier', {'n': t.minItems, 'p': t.percent})).join('  ·  '),
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class KeyValueRow extends StatelessWidget {
  const KeyValueRow(this.label, this.value, {super.key, this.bold = false, this.color});

  final String label;
  final String value;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.normal, fontSize: bold ? 16 : 14, color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [Expanded(child: Text(label, style: style)), Text(value, style: style)]),
    );
  }
}
