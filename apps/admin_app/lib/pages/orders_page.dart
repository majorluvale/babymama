import 'package:babymama_core/babymama_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../widgets.dart';

const _statuses = ['PENDING_PAYMENT', 'CONFIRMED', 'PREPARING', 'READY', 'OUT_FOR_DELIVERY', 'DELIVERED', 'CANCELLED', 'REFUNDED'];

/// Mirrors the server workflow (backend/src/modules/admin/orders.admin.ts).
const _next = <String, List<String>>{
  'PENDING_PAYMENT': ['CONFIRMED'],
  'CONFIRMED': ['PREPARING', 'READY'],
  'PREPARING': ['READY'],
  'READY': ['PREPARING', 'OUT_FOR_DELIVERY'],
  'OUT_FOR_DELIVERY': ['DELIVERED', 'READY'],
  'DELIVERED': ['REFUNDED'],
  'CANCELLED': ['REFUNDED'],
};

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  final _search = TextEditingController();
  String? _status;
  int _page = 1;
  int _version = 0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    return Scaffold(
      appBar: PageHeader(
        title: context.tr('admin_orders'),
        actions: [IconButton(onPressed: () => setState(() => _version++), icon: const Icon(Icons.refresh))],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(children: [
          TextField(
            controller: _search,
            decoration: InputDecoration(hintText: context.tr('search_orders_admin'), prefixIcon: const Icon(Icons.search)),
            onSubmitted: (_) => setState(() {
              _page = 1;
              _version++;
            }),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 44,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              ChoiceChip(
                label: Text(context.tr('all')),
                selected: _status == null,
                onSelected: (_) => setState(() {
                  _status = null;
                  _page = 1;
                }),
              ),
              for (final s in _statuses)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: ChoiceChip(
                    label: Text(context.tr('status_$s')),
                    selected: _status == s,
                    onSelected: (_) => setState(() {
                      _status = s;
                      _page = 1;
                    }),
                  ),
                ),
            ]),
          ),
          Expanded(
            child: AsyncBuilder<Paged<Order>>(
              key: ValueKey('$_status|$_page|$_version'),
              load: () async => Paged.fromJson(
                await api.get('/admin/orders', query: {'status': _status, 'q': _search.text.trim(), 'page': _page, 'pageSize': 30})
                    as Json,
                Order.fromJson,
              ),
              builder: (context, page, reload) {
                if (page.items.isEmpty) return EmptyView(icon: Icons.receipt_long_outlined, message: context.tr('no_orders'));
                return Column(children: [
                  Expanded(
                    child: ListView.separated(
                      itemCount: page.items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final o = page.items[i];
                        final driver = o.delivery?.driver;
                        return ListTile(
                          title: Text('${o.number} · ${o.customer?.name ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text([
                            formatDateTime(o.createdAt),
                            o.zoneName,
                            context.tr('items_count', {'n': o.itemCount}),
                            context.tr('pay_${o.paymentMethod}'),
                            driver != null ? '${context.tr('rider')}: ${driver.name}' : context.tr('no_rider'),
                          ].join(' · ')),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(formatKes(o.total), style: const TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(width: 12),
                            StatusChip(o.paymentStatus, prefix: 'payment_status_'),
                            const SizedBox(width: 8),
                            StatusChip(o.status),
                          ]),
                          onTap: () async {
                            await showDialog<void>(context: context, builder: (_) => OrderAdminDialog(orderId: o.id));
                            reload();
                          },
                        );
                      },
                    ),
                  ),
                  Pager(page: page.page, pages: page.pages, total: page.total, onPage: (p) => setState(() => _page = p)),
                ]);
              },
            ),
          ),
        ]),
      ),
    );
  }
}

class OrderAdminDialog extends StatefulWidget {
  const OrderAdminDialog({super.key, required this.orderId});

  final String orderId;

  @override
  State<OrderAdminDialog> createState() => _OrderAdminDialogState();
}

class _OrderAdminDialogState extends State<OrderAdminDialog> {
  Order? _order;
  List<BmUser> _drivers = [];
  bool _busy = false;

  ApiClient get _api => context.read<ApiClient>();

  @override
  void initState() {
    super.initState();
    _load();
    _api.get('/admin/drivers').then((list) {
      if (mounted) {
        setState(() => _drivers = (list as List).whereType<Json>().map(BmUser.fromJson).where((u) => u.isActive).toList());
      }
    }).catchError((_) {});
  }

  Future<void> _load() async {
    final o = Order.fromJson(await _api.get('/admin/orders/${widget.orderId}') as Json);
    if (mounted) setState(() => _order = o);
  }

  Future<void> _do(Future<dynamic> Function() call) async {
    setState(() => _busy = true);
    final ok = await runApi(context, () async {
      final res = await call();
      if (res is Json && mounted) setState(() => _order = Order.fromJson(res));
    });
    if (mounted) setState(() => _busy = false);
    if (!ok) _load();
  }

  @override
  Widget build(BuildContext context) {
    final o = _order;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 760),
        child: o == null
            ? const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()))
            : ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Row(children: [
                    Expanded(child: Text(o.number, style: Theme.of(context).textTheme.headlineSmall)),
                    StatusChip(o.status),
                    IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                  ]),
                  Text(formatDateTime(o.createdAt)),
                  if (o.cancelReason != null) Text(o.cancelReason!, style: const TextStyle(color: BmColors.danger)),
                  const Divider(height: 24),
                  Text(context.tr('customer'), style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('${o.customer?.name} · ${o.customer?.email} · ${o.customer?.phone ?? ''}'),
                  const SizedBox(height: 8),
                  Text(context.tr('delivery_address'), style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('${o.recipientName} · ${o.phone}\n${o.street}${o.landmark != null ? ' (${o.landmark})' : ''} · ${o.zoneName}'),
                  if (o.notes != null) Text('${context.tr('order_notes')}: ${o.notes}'),
                  Text('${context.tr('delivery_code')}: ${o.deliveryCode ?? '-'}'),
                  const Divider(height: 24),
                  for (final item in o.items)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: BmImage(item.imageUrl, width: 40, height: 40, radius: 4),
                      title: Text('${item.bundleId != null ? '[${context.tr('bundle')}] ' : ''}${item.title}'),
                      trailing: Text('${item.quantity} × ${formatKes(item.unitPrice)}'),
                    ),
                  Text(
                    '${context.tr('subtotal')} ${formatKes(o.subtotal)} · ${context.tr('discount')} -${formatKes(o.discount)} · '
                    '${context.tr('delivery')} ${formatKes(o.deliveryFee)} · ${context.tr('total')} ${formatKes(o.total)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Row(children: [
                    Text(context.tr('pay_${o.paymentMethod}')),
                    const SizedBox(width: 8),
                    StatusChip(o.paymentStatus, prefix: 'payment_status_'),
                  ]),
                  if (o.review != null) ...[
                    const Divider(height: 24),
                    RatingStars(rating: o.review!.rating),
                    if (o.review!.comment != null) Text(o.review!.comment!),
                  ],
                  const Divider(height: 24),
                  Text(context.tr('rider'), style: const TextStyle(fontWeight: FontWeight.w700)),
                  Row(children: [
                    Expanded(
                      child: DropdownButton<String?>(
                        isExpanded: true,
                        value: _drivers.any((d) => d.id == o.delivery?.driver?.id) ? o.delivery?.driver?.id : null,
                        hint: Text(context.tr('assign_rider')),
                        items: [
                          DropdownMenuItem<String?>(value: null, child: Text(context.tr('no_rider'))),
                          for (final d in _drivers) DropdownMenuItem<String?>(value: d.id, child: Text('${d.name} · ${d.phone ?? ''}')),
                        ],
                        onChanged: _busy || o.status == 'DELIVERED' || o.status == 'CANCELLED'
                            ? null
                            : (id) => _do(() => _api.post('/admin/orders/${o.id}/assign', {'driverId': id})),
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (o.delivery != null) StatusChip(o.delivery!.status, prefix: 'delivery_status_'),
                  ]),
                  if (o.delivery?.failedReason != null)
                    Text(o.delivery!.failedReason!, style: const TextStyle(color: BmColors.danger)),
                  const Divider(height: 24),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final s in _next[o.status] ?? const <String>[])
                      FilledButton.tonal(
                        onPressed: _busy ? null : () => _do(() => _api.patch('/admin/orders/${o.id}', {'status': s})),
                        child: Text('→ ${context.tr('status_$s')}'),
                      ),
                    if (o.paymentStatus != 'PAID' && o.status != 'CANCELLED')
                      OutlinedButton(
                        onPressed: _busy ? null : () => _do(() => _api.patch('/admin/orders/${o.id}', {'paymentStatus': 'PAID'})),
                        child: Text(context.tr('mark_paid')),
                      ),
                    if (o.status != 'DELIVERED' && o.status != 'CANCELLED' && o.status != 'REFUNDED')
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                final reason = await promptText(context, context.tr('cancel_reason'));
                                if (reason != null && reason.length >= 3) {
                                  _do(() => _api.post('/admin/orders/${o.id}/cancel', {'reason': reason}));
                                }
                              },
                        child: Text(context.tr('cancel_order'), style: const TextStyle(color: BmColors.danger)),
                      ),
                  ]),
                ],
              ),
      ),
    );
  }
}
