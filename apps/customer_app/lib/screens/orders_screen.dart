import 'package:babymama_core/babymama_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../widgets/shop_widgets.dart';
import '../widgets/site_layout.dart';
import 'payment_screen.dart';
import 'support_screen.dart';

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    return SiteScaffold(
      title: context.tr('my_orders'),
      body: AsyncBuilder<Paged<Order>>(
        load: () async => Paged.fromJson(await api.get('/orders', query: {'pageSize': 50}) as Json, Order.fromJson),
        builder: (context, page, reload) {
          if (page.items.isEmpty) {
            return EmptyView(icon: Icons.receipt_long_outlined, message: context.tr('no_orders'));
          }
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: page.items.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, i) {
                final o = page.items[i];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: BmImage(o.items.isEmpty ? null : o.items.first.imageUrl, width: 56, height: 56, radius: 8),
                  title: Text(o.number, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${formatDate(o.createdAt)} · ${context.tr('items_count', {'n': o.itemCount})}'),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(formatKes(o.total), style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      StatusChip(o.status),
                    ],
                  ),
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: o.id)));
                    reload();
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}

const _steps = ['CONFIRMED', 'PREPARING', 'OUT_FOR_DELIVERY', 'DELIVERED'];

class OrderDetailScreen extends StatelessWidget {
  const OrderDetailScreen({super.key, required this.orderId, this.justPlaced = false});

  final String orderId;
  final bool justPlaced;

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    return SiteScaffold(
      title: context.tr('order_details'),
      body: AsyncBuilder<Order>(
        load: () async => Order.fromJson(await api.get('/orders/$orderId') as Json),
        builder: (context, order, reload) => RefreshIndicator(
          onRefresh: reload,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: _OrderBody(order: order, reload: reload, justPlaced: justPlaced),
            ),
          ),
        ),
      ),
    );
  }
}

class _OrderBody extends StatelessWidget {
  const _OrderBody({required this.order, required this.reload, required this.justPlaced});

  final Order order;
  final Future<void> Function() reload;
  final bool justPlaced;

  Future<void> _cancel(BuildContext context) async {
    if (!await confirmDialog(context, context.tr('cancel_order_confirm'))) return;
    if (!context.mounted) return;
    try {
      await context.read<ApiClient>().post('/orders/${order.id}/cancel');
      await reload();
    } on ApiException catch (e) {
      if (context.mounted) showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = order;
    final d = o.delivery;
    final stepIndex = _steps.indexOf(o.status == 'READY' ? 'PREPARING' : o.status);
    final showCode = o.deliveryCode != null && ['CONFIRMED', 'PREPARING', 'READY', 'OUT_FOR_DELIVERY'].contains(o.status);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (justPlaced)
          Card(
            elevation: 0,
            color: BmColors.success.withAlpha(30),
            child: ListTile(
              leading: const Icon(Icons.check_circle, color: BmColors.success),
              title: Text(context.tr('order_thanks')),
              subtitle: Text(context.tr('order_thanks_sub')),
            ),
          ),
        Row(children: [
          Expanded(
            child: Text(o.number, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          ),
          StatusChip(o.status),
        ]),
        Text(formatDateTime(o.createdAt), style: const TextStyle(color: BmColors.muted)),
        if (o.cancelReason != null) Text(o.cancelReason!, style: const TextStyle(color: BmColors.danger)),
        const SizedBox(height: 16),
        if (stepIndex >= 0)
          Row(
            children: [
              for (var i = 0; i < _steps.length; i++) ...[
                Expanded(
                  child: Column(children: [
                    Icon(i <= stepIndex ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: i <= stepIndex ? BmColors.primary : BmColors.muted),
                    const SizedBox(height: 4),
                    Text(context.tr('status_${_steps[i]}'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 11)),
                  ]),
                ),
              ],
            ],
          ),
        if (showCode) ...[
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            color: BmColors.primary.withAlpha(20),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                const Icon(Icons.lock_outline, color: BmColors.primary),
                const SizedBox(width: 12),
                Expanded(child: Text(context.tr('delivery_code_hint'))),
                Text(o.deliveryCode!,
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 4, color: BmColors.primary)),
              ]),
            ),
          ),
        ],
        if (d?.driver != null) ...[
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(child: Icon(Icons.delivery_dining)),
            title: Text(d!.driver!.name),
            subtitle: Text(context.tr('delivery_status_${d.status}')),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (d.lastLat != null && d.lastLng != null)
                IconButton(
                  tooltip: context.tr('track_on_map'),
                  icon: const Icon(Icons.map_outlined),
                  onPressed: () => openExternal('https://www.google.com/maps/search/?api=1&query=${d.lastLat},${d.lastLng}'),
                ),
              if (d.driver!.phone != null)
                IconButton(
                  tooltip: context.tr('call_rider'),
                  icon: const Icon(Icons.call_outlined),
                  onPressed: () => openExternal('tel:${d.driver!.phone}'),
                ),
            ]),
          ),
        ],
        const Divider(height: 32),
        for (final item in o.items)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: BmImage(item.imageUrl, width: 52, height: 52, radius: 8),
            title: Text(item.title),
            subtitle: Text('${item.quantity} × ${formatKes(item.unitPrice)}'),
            trailing: Text(formatKes(item.unitPrice * item.quantity)),
            onTap: item.productId != null
                ? () => openProduct(context, item.productId!)
                : (item.bundleId != null ? () => openBundle(context, item.bundleId!) : null),
          ),
        const Divider(height: 24),
        KeyValueRow(context.tr('subtotal'), formatKes(o.subtotal)),
        if (o.discount > 0)
          KeyValueRow(context.tr('multibuy_discount', {'p': o.discountPercent}), '-${formatKes(o.discount)}', color: BmColors.success),
        KeyValueRow('${context.tr('delivery')} (${o.zoneName})', formatKes(o.deliveryFee)),
        KeyValueRow(context.tr('total'), formatKes(o.total), bold: true),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Text(context.tr('pay_${o.paymentMethod}'))),
          StatusChip(o.paymentStatus, prefix: 'payment_status_'),
        ]),
        const Divider(height: 32),
        Text(context.tr('delivery_address'), style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('${o.recipientName} · ${o.phone}\n${o.street}${o.landmark != null ? '\n${o.landmark}' : ''}\n${o.zoneName}, Nairobi'),
        if (o.review != null) ...[
          const Divider(height: 32),
          Text(context.tr('your_review'), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          RatingStars(rating: o.review!.rating),
          if (o.review!.comment != null) Text(o.review!.comment!),
        ],
        const SizedBox(height: 24),
        if (o.canPay)
          FilledButton(
            onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => PaymentScreen(order: o))),
            child: Text(context.tr('pay_now')),
          ),
        if (o.canReview)
          FilledButton.icon(
            icon: const Icon(Icons.star_outline),
            onPressed: () async {
              final done = await showReviewSheet(context, o);
              if (done) reload();
            },
            label: Text(context.tr('rate_order')),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.support_agent),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => NewTicketScreen(orderId: o.id, orderNumber: o.number)),
          ),
          label: Text(context.tr('contact_support')),
        ),
        if (o.canCancel)
          TextButton(
            onPressed: () => _cancel(context),
            child: Text(context.tr('cancel_order'), style: const TextStyle(color: BmColors.danger)),
          ),
      ],
    );
  }
}

/// Customer rates the order (and the rider). Returns true when submitted.
Future<bool> showReviewSheet(BuildContext context, Order order) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ReviewSheet(order: order),
  );
  return result ?? false;
}

class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet({required this.order});

  final Order order;

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  int _rating = 5;
  int _driverRating = 5;
  final _comment = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await context.read<ApiClient>().post('/orders/${widget.order.id}/review', {
        'rating': _rating,
        if (widget.order.delivery?.driver != null) 'driverRating': _driverRating,
        if (_comment.text.trim().isNotEmpty) 'comment': _comment.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('rate_order'), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Text(context.tr('rate_items')),
          RatingStars(rating: _rating, size: 36, onChanged: (v) => setState(() => _rating = v)),
          if (widget.order.delivery?.driver != null) ...[
            const SizedBox(height: 12),
            Text(context.tr('rate_rider', {'name': widget.order.delivery!.driver!.name})),
            RatingStars(rating: _driverRating, size: 36, onChanged: (v) => setState(() => _driverRating = v)),
          ],
          const SizedBox(height: 12),
          TextField(controller: _comment, maxLines: 3, decoration: InputDecoration(labelText: context.tr('comment_optional'))),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: _busy ? null : _submit, child: Text(context.tr('submit'))),
          ),
        ],
      ),
    );
  }
}
