import 'package:babymama_core/babymama_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/cart.dart';
import '../widgets/shop_widgets.dart';
import '../widgets/site_layout.dart';

/// Bundle sale ("vente groupée"): several items sold together at a reduced price.
class BundleScreen extends StatelessWidget {
  const BundleScreen({super.key, required this.bundleId});

  final String bundleId;

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    return SiteScaffold(
      title: context.tr('bundle'),
      body: AsyncBuilder<Bundle>(
        load: () async => Bundle.fromJson(await api.get('/bundles/$bundleId') as Json),
        builder: (context, b, _) {
          final lang = context.lang;
          final inCart = context.watch<CartController>().quantityOf('bundle', b.id);
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  AspectRatio(aspectRatio: 16 / 9, child: BmImage(b.imageUrl)),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(b.localizedTitle(lang),
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Row(children: [
                          Text(formatKes(b.price),
                              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: BmColors.primary)),
                          const SizedBox(width: 10),
                          Text(formatKes(b.originalPrice),
                              style: const TextStyle(color: BmColors.muted, decoration: TextDecoration.lineThrough)),
                          const SizedBox(width: 10),
                          if (b.savingPercent > 0)
                            Text(context.tr('you_save_p', {'p': b.savingPercent}),
                                style: const TextStyle(color: BmColors.success, fontWeight: FontWeight.w600)),
                        ]),
                        if (b.description.isNotEmpty) ...[const SizedBox(height: 12), Text(b.description)],
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: b.available > inCart
                              ? () {
                                  final ok = context.read<CartController>().addBundle(b, lang);
                                  showSnack(context, ok ? context.tr('added_to_cart') : context.tr('max_stock_reached'));
                                }
                              : null,
                          icon: const Icon(Icons.shopping_bag_outlined),
                          label: Text(b.available > 0 ? context.tr('add_bundle_to_cart') : context.tr('sold_out')),
                        ),
                        SectionHeader(context.tr('bundle_items', {'n': b.items.length})),
                      ],
                    ),
                  ),
                  for (final item in b.items)
                    ListTile(
                      leading: BmImage(item.product.image, width: 56, height: 56, radius: 8),
                      title: Text(item.product.title),
                      subtitle: Text([
                        item.product.size,
                        context.tr('condition_${item.product.condition}'),
                        if (item.quantity > 1) 'x${item.quantity}',
                      ].whereType<String>().join(' · ')),
                      trailing: Text(formatKes(item.product.price),
                          style: const TextStyle(color: BmColors.muted, decoration: TextDecoration.lineThrough)),
                      onTap: () => openProduct(context, item.productId),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
