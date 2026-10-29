import 'package:babymama_core/babymama_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../widgets.dart';
import 'products_page.dart';

/// Stock management: summary, low-stock alerts and the full movement ledger.
class StockPage extends StatefulWidget {
  const StockPage({super.key});

  @override
  State<StockPage> createState() => _StockPageState();
}

class _StockPageState extends State<StockPage> {
  int _version = 0;
  int _page = 1;

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: PageHeader(
          title: context.tr('admin_stock'),
          actions: [IconButton(onPressed: () => setState(() => _version++), icon: const Icon(Icons.refresh))],
          bottom: TabBar(tabs: [Tab(text: context.tr('low_stock')), Tab(text: context.tr('stock_movements'))]),
        ),
        body: Column(
          children: [
            AsyncBuilder<Json>(
              key: ValueKey('summary$_version'),
              load: () async => await api.get('/admin/stock/summary') as Json,
              builder: (context, s, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(spacing: 12, runSpacing: 12, children: [
                  StatCard(label: context.tr('active_products'), value: '${s['activeProducts']}', icon: Icons.checkroom_outlined),
                  StatCard(label: context.tr('units_in_stock'), value: '${s['totalUnits']}', icon: Icons.inventory_2_outlined),
                  StatCard(label: context.tr('stock_value'), value: formatKes((s['stockValue'] as num?) ?? 0), icon: Icons.savings_outlined),
                  StatCard(label: context.tr('low_stock'), value: '${s['lowStock']}', icon: Icons.warning_amber, color: BmColors.warning),
                  StatCard(label: context.tr('product_status_SOLD_OUT'), value: '${s['soldOut']}', icon: Icons.block, color: BmColors.danger),
                ]),
              ),
            ),
            Expanded(
              child: TabBarView(children: [
                AsyncBuilder<Paged<Product>>(
                  key: ValueKey('low$_version'),
                  load: () async => Paged.fromJson(
                    await api.get('/admin/products', query: {'lowStock': 'true', 'pageSize': 100}) as Json,
                    Product.fromJson,
                  ),
                  builder: (context, page, reload) {
                    if (page.items.isEmpty) return EmptyView(icon: Icons.check_circle_outline, message: context.tr('no_low_stock'));
                    return ListView.separated(
                      itemCount: page.items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final p = page.items[i];
                        return ListTile(
                          leading: BmImage(p.image, width: 44, height: 44, radius: 6),
                          title: Text(p.title),
                          subtitle: Text('${p.sku} · ${context.tr('low_stock_threshold')}: ${p.lowStockThreshold}'),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text('${p.stock}', style: const TextStyle(fontWeight: FontWeight.w800, color: BmColors.danger, fontSize: 18)),
                            const SizedBox(width: 12),
                            FilledButton.tonal(
                              onPressed: () async {
                                if (await showStockDialog(context, p)) setState(() => _version++);
                              },
                              child: Text(context.tr('restock')),
                            ),
                          ]),
                        );
                      },
                    );
                  },
                ),
                AsyncBuilder<Json>(
                  key: ValueKey('moves$_version|$_page'),
                  load: () async => await api.get('/admin/stock/movements', query: {'page': _page, 'pageSize': 50}) as Json,
                  builder: (context, res, _) {
                    final items = ((res['items'] as List?) ?? const []).whereType<Json>().toList();
                    return Column(children: [
                      Expanded(
                        child: ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final m = items[i];
                            final qty = (m['quantity'] as num).toInt();
                            final product = (m['product'] as Json?) ?? const {};
                            final order = m['order'] as Json?;
                            final user = m['user'] as Json?;
                            final created = DateTime.tryParse('${m['createdAt']}')?.toLocal();
                            return ListTile(
                              dense: true,
                              leading: Text(qty > 0 ? '+$qty' : '$qty',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800, fontSize: 16, color: qty > 0 ? BmColors.success : BmColors.danger)),
                              title: Text('${product['title']} (${product['sku']})'),
                              subtitle: Text([
                                context.tr('movement_${m['type']}'),
                                if (order != null) 'BM-${'${order['seq']}'.padLeft(6, '0')}',
                                if (m['reason'] != null) '${m['reason']}',
                                if (user != null) '${user['name']}',
                              ].join(' · ')),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('→ ${m['stockAfter']}'),
                                  if (created != null) Text(formatDateTime(created), style: const TextStyle(fontSize: 11, color: BmColors.muted)),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      Pager(
                        page: (res['page'] as num?)?.toInt() ?? 1,
                        pages: (res['pages'] as num?)?.toInt() ?? 1,
                        total: (res['total'] as num?)?.toInt() ?? 0,
                        onPage: (p) => setState(() => _page = p),
                      ),
                    ]);
                  },
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
