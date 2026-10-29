import 'package:babymama_core/babymama_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/cart.dart';
import '../state/favorites.dart';
import '../widgets/shop_widgets.dart';
import '../widgets/site_layout.dart';

class ProductScreen extends StatelessWidget {
  const ProductScreen({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    return SiteScaffold(
      fullWidth: true,
      body: AsyncBuilder<Product>(
        load: () async => Product.fromJson(await api.get('/products/$productId') as Json),
        builder: (context, p, _) => _ProductView(product: p),
      ),
    );
  }
}

class _ProductView extends StatelessWidget {
  const _ProductView({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= kWideBreakpoint;
    final gutter = siteGutter(width);

    if (wide) {
      // The footer spans the full width, so only the product part gets the side gutter.
      return ListView(
        padding: const EdgeInsets.only(top: 24),
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: gutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Breadcrumb(product: p),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 6, child: _Gallery(images: p.images, thumbnails: true)),
                    const SizedBox(width: 48),
                    Expanded(flex: 5, child: _Details(product: p, showButtons: true)),
                  ],
                ),
                if (p.related.isNotEmpty) ...[
                  const SizedBox(height: 48),
                  Text(context.tr('similar_items'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 16),
                  ProductStrip(products: p.related),
                ],
              ],
            ),
          ),
          const SiteFooter(),
        ],
      );
    }

    return Column(children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _Gallery(images: p.images),
            Padding(padding: const EdgeInsets.all(16), child: _Details(product: p, showButtons: false)),
            if (p.related.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(context.tr('similar_items'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  ProductStrip(products: p.related),
                ]),
              ),
          ],
        ),
      ),
      SafeArea(
        child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), child: _BuyButtons(product: p)),
      ),
    ]);
  }
}

/// Home › Women › Dresses
class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final lang = context.lang;
    final c = product.category;
    final parts = <(String, VoidCallback)>[
      (context.tr('nav_home'), () => goHome(context)),
      if (c?.parent != null) (c!.parent!.name(lang), () => openCatalog(context, categoryId: c.parent!.id)),
      if (c != null) (c.name(lang), () => openCatalog(context, categoryId: c.id)),
    ];
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final (i, (label, onTap)) in parts.indexed) ...[
          if (i > 0) const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('›', style: TextStyle(color: BmColors.muted))),
          InkWell(onTap: onTap, child: Text(label, style: const TextStyle(color: BmColors.muted, fontSize: 13))),
        ],
      ],
    );
  }
}

class _BuyButtons extends StatelessWidget {
  const _BuyButtons({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final inCart = context.watch<CartController>().quantityOf('product', p.id);
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: p.isAvailable && inCart < p.stock ? () => addProductToCart(context, p) : null,
            child: Text(inCart > 0 ? context.tr('in_cart_n', {'n': inCart}) : context.tr('add_to_cart')),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: BmColors.ink),
            onPressed: p.isAvailable
                ? () {
                    if (inCart == 0) context.read<CartController>().addProduct(p);
                    openCart(context);
                  }
                : null,
            child: Text(p.isAvailable ? context.tr('buy_now') : context.tr('sold_out')),
          ),
        ),
      ],
    );
  }
}

/// Photos with left / right arrows, page dots, and thumbnails on the website.
class _Gallery extends StatefulWidget {
  const _Gallery({required this.images, this.thumbnails = false});

  final List<String> images;
  final bool thumbnails;

  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go(int i) {
    final count = widget.images.length;
    if (count < 2) return;
    _controller.animateToPage((i + count) % count, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.images.isEmpty ? <String?>[null] : widget.images;
    final many = images.length > 1;
    final main = AspectRatio(
      aspectRatio: 3 / 4,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.thumbnails ? 6 : 0),
        child: Stack(
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: images.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) => BmImage(images[i], fit: BoxFit.cover),
            ),
            if (many) ...[
              Positioned(left: 12, top: 0, bottom: 0, child: Center(child: CarouselArrow(left: true, onPressed: () => _go(_index - 1)))),
              Positioned(right: 12, top: 0, bottom: 0, child: Center(child: CarouselArrow(left: false, onPressed: () => _go(_index + 1)))),
              Positioned(
                bottom: 12,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white.withAlpha(230), borderRadius: BorderRadius.circular(12)),
                    child: Text('${_index + 1} / ${images.length}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
    if (!widget.thumbnails || !many) return main;
    return Column(
      children: [
        main,
        const SizedBox(height: 12),
        Row(
          children: [
            for (final (i, url) in images.indexed) ...[
              if (i > 0) const SizedBox(width: 10),
              GestureDetector(
                onTap: () => _go(i),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Container(
                    width: 72,
                    height: 96,
                    decoration: BoxDecoration(
                      border: Border.all(color: i == _index ? BmColors.ink : Colors.transparent, width: 2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    padding: const EdgeInsets.all(2),
                    child: BmImage(url, radius: 2),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.product, required this.showButtons});

  final Product product;
  final bool showButtons;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final lang = context.lang;
    final favorite = context.watch<FavoritesController>().isFavorite(p.id);
    final attributes = <(String, Widget)>[
      if (p.size != null) (context.tr('size'), Text(p.size!, style: const TextStyle(fontWeight: FontWeight.w600))),
      if (p.color != null)
        (
          context.tr('color'),
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (productColors.containsKey(p.color)) ...[ColorSwatchDot(p.color!, size: 14), const SizedBox(width: 6)],
            Text(context.colorName(p.color!), style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
        ),
      (context.tr('condition'), Text(context.tr('condition_${p.condition}'), style: const TextStyle(fontWeight: FontWeight.w600))),
      if (p.brand != null) (context.tr('brand'), Text(p.brand!, style: const TextStyle(fontWeight: FontWeight.w600))),
      if (p.category != null)
        (
          context.tr('category'),
          InkWell(
            onTap: () => openCatalog(context, categoryId: p.category!.id),
            child: Text(p.category!.path(lang), style: const TextStyle(fontWeight: FontWeight.w600, decoration: TextDecoration.underline)),
          ),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (p.category != null)
          Text(p.category!.path(lang).toUpperCase(),
              style: const TextStyle(color: BmColors.muted, fontSize: 12, letterSpacing: 1, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(p.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            ),
            IconButton(
              tooltip: context.tr('favorites'),
              icon: Icon(favorite ? Icons.favorite : Icons.favorite_border, color: favorite ? BmColors.accent : null),
              onPressed: () => toggleFavorite(context, p.id),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(formatKes(p.price), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            if (p.compareAtPrice != null && p.compareAtPrice! > p.price) ...[
              const SizedBox(width: 10),
              Text(formatKes(p.compareAtPrice!), style: const TextStyle(color: BmColors.muted, decoration: TextDecoration.lineThrough)),
            ],
          ],
        ),
        const SizedBox(height: 4),
        if (!p.isAvailable)
          Text(context.tr('sold_out'), style: const TextStyle(color: BmColors.danger, fontWeight: FontWeight.w600))
        else if (p.stock <= 3)
          Text(context.tr('only_n_left', {'n': p.stock}), style: const TextStyle(color: BmColors.warning, fontWeight: FontWeight.w600)),
        const SizedBox(height: 20),
        Container(
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: BmColors.line))),
          child: Column(
            children: [
              for (final (label, value) in attributes)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: BmColors.line))),
                  child: Row(children: [
                    SizedBox(width: 110, child: Text(label, style: const TextStyle(color: BmColors.muted))),
                    Expanded(child: Align(alignment: Alignment.centerLeft, child: value)),
                  ]),
                ),
            ],
          ),
        ),
        if (showButtons) ...[
          const SizedBox(height: 24),
          _BuyButtons(product: p),
        ],
        const SizedBox(height: 20),
        if (p.discountTiers.isNotEmpty) ...[
          DiscountTiersBanner(tiers: p.discountTiers),
          const SizedBox(height: 20),
        ],
        Text(context.tr('description'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 6),
        Text(p.description.isEmpty ? '-' : p.description, style: const TextStyle(height: 1.5)),
        const SizedBox(height: 16),
        Row(children: [
          const Icon(Icons.verified_outlined, size: 18, color: BmColors.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(context.tr('quality_checked'), style: const TextStyle(color: BmColors.muted))),
        ]),
        const SizedBox(height: 8),
        Text('SKU ${p.sku}', style: const TextStyle(color: BmColors.muted, fontSize: 12)),
      ],
    );
  }
}
