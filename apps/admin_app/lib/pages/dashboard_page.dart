import 'dart:math' as math;

import 'package:babymama_core/babymama_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../widgets.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    return Scaffold(
      appBar: PageHeader(title: context.tr('admin_dashboard')),
      body: AsyncBuilder<Json>(
        load: () async => await api.get('/admin/stats') as Json,
        builder: (context, s, reload) {
          final byStatus = (s['ordersByStatus'] as Json?) ?? const {};
          final days = ((s['last7Days'] as List?) ?? const []).whereType<Json>().toList();
          final lowStock = ((s['lowStock'] as List?) ?? const []).whereType<Json>().toList();
          final maxRevenue = days.fold<num>(1, (m, d) => math.max(m, (d['revenue'] as num?) ?? 0));

          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Wrap(spacing: 12, runSpacing: 12, children: [
                  StatCard(label: context.tr('revenue_today'), value: formatKes((s['revenueToday'] as num?) ?? 0), icon: Icons.payments_outlined),
                  StatCard(label: context.tr('orders_today'), value: '${s['ordersToday'] ?? 0}', icon: Icons.receipt_long_outlined),
                  StatCard(
                    label: context.tr('to_dispatch'),
                    value: '${s['deliveriesToDispatch'] ?? 0}',
                    icon: Icons.delivery_dining_outlined,
                    color: BmColors.warning,
                  ),
                  StatCard(label: context.tr('open_tickets'), value: '${s['openTickets'] ?? 0}', icon: Icons.support_agent, color: BmColors.accent),
                  StatCard(
                    label: context.tr('pending_listings'),
                    value: '${s['pendingListings'] ?? 0}',
                    icon: Icons.fact_check_outlined,
                    color: BmColors.warning,
                  ),
                  StatCard(
                    label: context.tr('refunds_to_process'),
                    value: '${s['refundsToProcess'] ?? 0}',
                    icon: Icons.undo,
                    color: BmColors.danger,
                  ),
                ]),
                const SizedBox(height: 24),
                Text(context.tr('last_7_days'), style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                SizedBox(
                  height: 180,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final d in days)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(formatKes((d['revenue'] as num?) ?? 0), style: const TextStyle(fontSize: 10)),
                                const SizedBox(height: 4),
                                Container(
                                  height: (120 * ((d['revenue'] as num?) ?? 0) / maxRevenue).toDouble(),
                                  decoration: BoxDecoration(color: BmColors.primary, borderRadius: BorderRadius.circular(4)),
                                ),
                                const SizedBox(height: 4),
                                Text('${d['date']}'.substring(5), style: const TextStyle(fontSize: 11, color: BmColors.muted)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(context.tr('orders_by_status'), style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final e in byStatus.entries)
                    Chip(avatar: CircleAvatar(child: Text('${e.value}', style: const TextStyle(fontSize: 11))), label: Text(context.tr('status_${e.key}'))),
                ]),
                const SizedBox(height: 24),
                Text(context.tr('low_stock'), style: Theme.of(context).textTheme.titleMedium),
                if (lowStock.isEmpty) Padding(padding: const EdgeInsets.all(8), child: Text(context.tr('no_low_stock'))),
                for (final p in lowStock)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.warning_amber, color: BmColors.warning),
                    title: Text('${p['title']}'),
                    subtitle: Text('${p['sku']}'),
                    trailing: Text('${context.tr('stock')}: ${p['stock']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
