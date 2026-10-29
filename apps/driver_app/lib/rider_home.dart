import 'package:babymama_core/babymama_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'delivery_screen.dart';
import 'location_reporter.dart';

class RiderHome extends StatefulWidget {
  const RiderHome({super.key});

  @override
  State<RiderHome> createState() => _RiderHomeState();
}

class _RiderHomeState extends State<RiderHome> {
  Json? _profile;
  bool _online = false;
  int _refreshKey = 0;

  ApiClient get _api => context.read<ApiClient>();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final p = await _api.get('/driver/me') as Json;
      if (!mounted) return;
      setState(() {
        _profile = p;
        _online = p['isOnline'] == true;
      });
      if (_online) context.read<LocationReporter>().start();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _setOnline(bool value) async {
    final reporter = context.read<LocationReporter>();
    if (value) {
      final ok = await reporter.start();
      if (!ok && mounted) showSnack(context, context.tr(reporter.error ?? 'location_denied'), error: true);
    } else {
      reporter.stop();
    }
    try {
      await _api.patch('/driver/me', {'isOnline': value});
      if (mounted) setState(() => _online = value);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  void _refresh() {
    setState(() => _refreshKey++);
    _loadProfile();
  }

  @override
  Widget build(BuildContext context) {
    final stats = (_profile?['stats'] as Json?) ?? const {};
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.read<Session>().user?.name ?? 'Rider'),
          actions: [
            Row(children: [
              Text(_online ? context.tr('online') : context.tr('offline'),
                  style: TextStyle(color: _online ? BmColors.success : BmColors.muted, fontWeight: FontWeight.w600)),
              Switch(value: _online, onChanged: _setOnline),
            ]),
            const LanguageMenu(),
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'logout') {
                  context.read<LocationReporter>().stop();
                  await _api.patch('/driver/me', {'isOnline': false}).catchError((_) => null);
                  if (context.mounted) await context.read<Session>().logout();
                }
              },
              itemBuilder: (ctx) => [PopupMenuItem(value: 'logout', child: Text(ctx.tr('sign_out')))],
            ),
          ],
          bottom: TabBar(tabs: [
            Tab(text: context.tr('tab_available')),
            Tab(text: context.tr('tab_my_deliveries')),
            Tab(text: context.tr('tab_history')),
          ]),
        ),
        body: Column(
          children: [
            Container(
              color: BmColors.surface,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              child: Row(
                children: [
                  _Stat(label: context.tr('delivered_today'), value: '${stats['deliveredToday'] ?? 0}'),
                  _Stat(label: context.tr('active'), value: '${stats['activeDeliveries'] ?? 0}'),
                  _Stat(label: context.tr('cash_today'), value: formatKes((stats['cashCollectedToday'] as num?) ?? 0)),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _DeliveryList(key: ValueKey('available$_refreshKey'), scope: 'available', onChanged: _refresh),
                  _DeliveryList(key: ValueKey('active$_refreshKey'), scope: 'active', onChanged: _refresh),
                  _DeliveryList(key: ValueKey('history$_refreshKey'), scope: 'history', onChanged: _refresh),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(children: [
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        Text(label, style: const TextStyle(fontSize: 12, color: BmColors.muted), textAlign: TextAlign.center),
      ]),
    );
  }
}

class _DeliveryList extends StatelessWidget {
  const _DeliveryList({super.key, required this.scope, required this.onChanged});

  final String scope;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    return AsyncBuilder<List<DriverDelivery>>(
      load: () async => (await api.get('/driver/deliveries', query: {'scope': scope}) as List)
          .whereType<Json>()
          .map(DriverDelivery.fromJson)
          .toList(),
      builder: (context, items, reload) {
        if (items.isEmpty) {
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(children: [
              const SizedBox(height: 80),
              EmptyView(icon: Icons.delivery_dining, message: context.tr('no_deliveries_$scope')),
            ]),
          );
        }
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final d = items[i];
              final o = d.order;
              return Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(12),
                  title: Row(children: [
                    Expanded(child: Text('${o.number} · ${o.zoneName}', style: const TextStyle(fontWeight: FontWeight.w700))),
                    StatusChip(d.status, prefix: 'delivery_status_'),
                  ]),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text([
                      o.recipientName,
                      o.street,
                      if (o.landmark != null) o.landmark!,
                      context.tr('items_count', {'n': o.itemCount}),
                      if (o.amountToCollect > 0) '${context.tr('collect_cash')}: ${formatKes(o.amountToCollect)}',
                    ].join('\n')),
                  ),
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => DeliveryScreen(deliveryId: d.id)));
                    onChanged();
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }
}
