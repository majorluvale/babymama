import 'package:babymama_core/babymama_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/categories.dart';
import '../widgets/shop_widgets.dart';
import '../widgets/site_layout.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    return SiteScaffold(
      fullWidth: true,
      showDepartments: true,
      body: AsyncBuilder<HomeFeed>(
        load: () async => HomeFeed.fromJson(await api.get('/home') as Json),
        builder: (context, feed, reload) => RefreshIndicator(
          onRefresh: reload,
          child: _HomeContent(feed: feed),
        ),
      ),
    );
  }
}

class _HomeContent extends StatelessWidget {
  const _HomeContent({required this.feed});

  final HomeFeed feed;

  @override
  Widget build(BuildContext context) {
    final lang = context.lang;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= kWideBreakpoint;
    final gutter = siteGutter(width);
    Widget padded(Widget child, {double top = 0}) =>
        Padding(padding: EdgeInsets.fromLTRB(gutter, top, gutter, 0), child: child);

    // Carousel: admin banners (promos, ads, categories...) followed by the latest arrivals.
    final slides = <Widget>[
      for (final b in feed.banners)
        CarouselSlide(
          imageUrl: b.imageUrl,
          title: b.title(lang),
          subtitle: b.subtitle(lang),
          cta: context.tr('shop_now'),
          onTap: () => openBanner(context, b),
        ),
      for (final p in feed.newArrivals.take(3))
        CarouselSlide(
          imageUrl: p.image,
          title: p.title,
          subtitle: [formatKes(p.price), p.category?.path(lang), if (p.size != null) '${context.tr('size')} ${p.size}']
              .whereType<String>()
              .join(' · '),
          badge: context.tr('badge_new_in'),
          cta: context.tr('view_item'),
          onTap: () => openProduct(context, p.id),
        ),
    ];

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: padded(PromoCarousel(slides: slides, height: wide ? 440 : 380), top: wide ? 24 : 12)),
        SliverToBoxAdapter(child: padded(const _DepartmentTiles(), top: 32)),
        SliverToBoxAdapter(child: padded(_SectionTitle(context.tr('shop_by_category')), top: 40)),
        SliverToBoxAdapter(child: padded(const _CategoryIndex())),
        if (feed.discountTiers.isNotEmpty) SliverToBoxAdapter(child: padded(DiscountTiersBanner(tiers: feed.discountTiers), top: 32)),
        if (feed.featured.isNotEmpty) ...[
          SliverToBoxAdapter(child: padded(_SectionTitle(context.tr('featured')), top: 40)),
          SliverToBoxAdapter(child: padded(ProductStrip(products: feed.featured))),
        ],
        if (feed.bundles.isNotEmpty) ...[
          SliverToBoxAdapter(child: padded(_SectionTitle(context.tr('bundles_title')), top: 40)),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 250,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: gutter),
                itemCount: feed.bundles.length,
                separatorBuilder: (_, __) => const SizedBox(width: 16),
                itemBuilder: (_, i) => BundleCard(bundle: feed.bundles[i]),
              ),
            ),
          ),
        ],
        SliverToBoxAdapter(
          child: padded(
            _SectionTitle(
              context.tr('new_arrivals'),
              actionLabel: context.tr('see_all'),
              onAction: () => openCatalog(context, sort: 'newest', title: context.tr('new_arrivals')),
            ),
            top: 40,
          ),
        ),
        if (feed.newArrivals.isEmpty)
          SliverToBoxAdapter(child: EmptyView(message: context.tr('no_products')))
        else
          ProductSliverGrid(products: feed.newArrivals),
        SliverToBoxAdapter(child: wide ? const SiteFooter() : const SizedBox(height: 32)),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700))),
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(foregroundColor: BmColors.ink),
              child: Row(mainAxisSize: MainAxisSize.min, children: [Text(actionLabel!), const Icon(Icons.chevron_right, size: 18)]),
            ),
        ],
      ),
    );
  }
}

/// Every sub-category with its icon, one column per department (stacked on phones).
class _CategoryIndex extends StatelessWidget {
  const _CategoryIndex();

  @override
  Widget build(BuildContext context) {
    final lang = context.lang;
    final categories = context.watch<CategoriesController>();
    final columns = [
      for (final d in categories.departments)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => openCatalog(context, categoryId: d.id, title: d.name(lang)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                CategoryIcon(d.icon, size: 22),
                const SizedBox(width: 8),
                Text(d.name(lang).toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2)),
              ]),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in categories.childrenOf(d.id))
                  CategoryChip(category: c, onTap: () => openCatalog(context, categoryId: c.id, title: c.path(lang))),
              ],
            ),
          ],
        ),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < 760) {
        return Column(children: [for (final c in columns) Padding(padding: const EdgeInsets.only(bottom: 20), child: c)]);
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, c) in columns.indexed) ...[
            if (i > 0) const SizedBox(width: 32),
            Expanded(child: c),
          ],
        ],
      );
    });
  }
}

/// The three departments as large photo tiles.
class _DepartmentTiles extends StatelessWidget {
  const _DepartmentTiles();

  @override
  Widget build(BuildContext context) {
    final lang = context.lang;
    final departments = context.watch<CategoriesController>().departments;
    if (departments.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, constraints) {
      final spacing = constraints.maxWidth >= 600 ? 24.0 : 10.0;
      return Row(
        children: [
          for (final (i, d) in departments.indexed) ...[
            if (i > 0) SizedBox(width: spacing),
            Expanded(
              child: _DepartmentTile(
                label: d.name(lang),
                imageUrl: d.imageUrl ?? 'https://picsum.photos/seed/babymama-${d.slug}/600/700',
                onTap: () => openCatalog(context, categoryId: d.id, title: d.name(lang)),
              ),
            ),
          ],
        ],
      );
    });
  }
}

class _DepartmentTile extends StatefulWidget {
  const _DepartmentTile({required this.label, required this.imageUrl, required this.onTap});

  final String label;
  final String imageUrl;
  final VoidCallback onTap;

  @override
  State<_DepartmentTile> createState() => _DepartmentTileState();
}

class _DepartmentTileState extends State<_DepartmentTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final small = MediaQuery.sizeOf(context).width < 600;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AspectRatio(
          aspectRatio: small ? 3 / 4 : 6 / 7,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Stack(
              fit: StackFit.expand,
              children: [
                AnimatedScale(scale: _hover ? 1.04 : 1, duration: const Duration(milliseconds: 300), child: BmImage(widget.imageUrl)),
                Positioned(
                  left: small ? 6 : 16,
                  right: small ? 6 : 16,
                  bottom: small ? 6 : 16,
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: small ? 8 : 14),
                    color: Colors.white,
                    alignment: Alignment.center,
                    child: Text(
                      widget.label.toUpperCase(),
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: small ? 12 : 16, letterSpacing: 1.5, color: BmColors.ink),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
