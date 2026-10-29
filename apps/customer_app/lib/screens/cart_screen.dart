import 'package:babymama_core/babymama_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/cart.dart';
import '../widgets/shop_widgets.dart';
import '../widgets/site_layout.dart';
import 'checkout_screen.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartController>();
    return SiteScaffold(
      title: context.tr('cart'),
      body: cart.isEmpty
          ? EmptyView(
              icon: Icons.shopping_bag_outlined,
              message: context.tr('cart_empty'),
              action: FilledButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('start_shopping'))),
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final line in cart.lines) _CartLineTile(line: line),
                    const SizedBox(height: 16),
                    _QuoteBox(key: ValueKey(cart.signature)),
                  ],
                ),
              ),
            ),
    );
  }
}

class _CartLineTile extends StatelessWidget {
  const _CartLineTile({required this.line});

  final CartLine line;

  @override
  Widget build(BuildContext context) {
    final cart = context.read<CartController>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          InkWell(
            onTap: () => line.isBundle ? openBundle(context, line.id) : openProduct(context, line.id),
            child: BmImage(line.image, width: 72, height: 90, radius: 8),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (line.isBundle)
                  Text(context.tr('bundle').toUpperCase(),
                      style: const TextStyle(fontSize: 11, color: BmColors.accent, fontWeight: FontWeight.w700)),
                Text(line.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                if ((line.subtitle ?? '').isNotEmpty)
                  Text(line.subtitle!, style: const TextStyle(color: BmColors.muted, fontSize: 12)),
                const SizedBox(height: 4),
                Text(formatKes(line.unitPrice * line.quantity), style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          Column(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => cart.setQuantity(line.key, line.quantity - 1),
                  ),
                  Text('${line.quantity}'),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: line.quantity < line.maxQuantity ? () => cart.setQuantity(line.key, line.quantity + 1) : null,
                  ),
                ],
              ),
              TextButton(onPressed: () => cart.remove(line.key), child: Text(context.tr('remove'))),
            ],
          ),
        ],
      ),
    );
  }
}

/// Server-side price check: current prices, stock and the multi-buy discount.
class _QuoteBox extends StatelessWidget {
  const _QuoteBox({super.key});

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    final cart = context.read<CartController>();
    return Card(
      elevation: 0,
      color: BmColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: AsyncBuilder<Quote>(
          load: () async => Quote.fromJson(await api.post('/orders/quote', cart.toPayload()) as Json),
          builder: (context, q, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KeyValueRow(context.tr('subtotal'), formatKes(q.subtotal)),
              if (q.discount > 0)
                KeyValueRow(context.tr('multibuy_discount', {'p': q.discountPercent}), '-${formatKes(q.discount)}',
                    color: BmColors.success),
              KeyValueRow(context.tr('delivery'), context.tr('calculated_at_checkout')),
              const Divider(),
              KeyValueRow(context.tr('total'), formatKes(q.subtotal - q.discount), bold: true),
              if (q.nextTier != null) ...[
                const SizedBox(height: 8),
                Text(
                  context.tr('next_tier_hint', {'n': q.nextTier!.minItems - q.itemCount, 'p': q.nextTier!.percent}),
                  style: const TextStyle(color: BmColors.accent, fontWeight: FontWeight.w600),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () async {
                  if (!await ensureLoggedIn(context)) return;
                  if (!context.mounted) return;
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CheckoutScreen()));
                },
                child: Text(context.tr('checkout')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
