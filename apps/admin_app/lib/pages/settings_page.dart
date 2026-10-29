import 'package:babymama_core/babymama_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../widgets.dart';

/// Delivery zones of Nairobi and the WooCommerce connection.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _version = 0;
  bool _syncing = false;

  Future<void> _editZone([DeliveryZone? zone]) async {
    final name = TextEditingController(text: zone?.name);
    final fee = TextEditingController(text: zone == null ? '' : '${zone.fee}');
    final eta = TextEditingController(text: '${zone?.etaMinutes ?? 90}');
    var active = zone?.active ?? true;
    final api = context.read<ApiClient>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(zone == null ? ctx.tr('new_zone') : zone.name),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: InputDecoration(labelText: ctx.tr('zone_name'))),
            TextField(controller: fee, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: ctx.tr('delivery_fee_kes'))),
            TextField(controller: eta, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: ctx.tr('eta_minutes_label'))),
            SwitchListTile(value: active, onChanged: (v) => setState(() => active = v), title: Text(ctx.tr('active'))),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('save'))),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final body = {
      'name': name.text.trim(),
      'fee': int.tryParse(fee.text.trim()) ?? 0,
      'etaMinutes': int.tryParse(eta.text.trim()) ?? 90,
      'active': active,
    };
    final saved = await runApi(context, () => zone == null ? api.post('/admin/zones', body) : api.patch('/admin/zones/${zone.id}', body));
    if (saved) setState(() => _version++);
  }

  Future<void> _wooAction(String path) async {
    final api = context.read<ApiClient>();
    setState(() => _syncing = true);
    try {
      final res = await api.post('/admin/woocommerce/$path') as Json;
      if (mounted) {
        showSnack(context, path == 'import'
            ? context.tr('woo_import_done', {'created': res['created'], 'updated': res['updated'], 'errors': (res['errors'] as List?)?.length ?? 0})
            : context.tr('woo_push_done', {'n': res['pushed']}));
      }
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    return Scaffold(
      appBar: PageHeader(title: context.tr('admin_settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('WooCommerce', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          AsyncBuilder<Json>(
            key: ValueKey('woo$_version'),
            load: () async => await api.get('/admin/woocommerce/status') as Json,
            builder: (context, s, _) {
              final enabled = s['enabled'] == true;
              return Card(
                elevation: 0,
                color: BmColors.surface,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(enabled ? Icons.check_circle : Icons.link_off, color: enabled ? BmColors.success : BmColors.muted),
                      const SizedBox(width: 8),
                      Expanded(child: Text(enabled ? '${context.tr('woo_connected')} ${s['url']}' : context.tr('woo_not_configured'))),
                    ]),
                    const SizedBox(height: 8),
                    Text('${context.tr('woo_linked_products')}: ${s['linkedProducts']}'),
                    Text('Webhook: ${s['webhookUrl']}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                    Text(context.tr('woo_webhook_help'), style: const TextStyle(color: BmColors.muted, fontSize: 12)),
                    Text(
                      '${context.tr('woo_push_stock')}: ${s['pushStock']} · ${context.tr('woo_push_products')}: ${s['pushProducts']} · '
                      '${context.tr('woo_push_orders')}: ${s['pushOrders']}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    Wrap(spacing: 12, children: [
                      FilledButton.icon(
                        onPressed: enabled && !_syncing ? () => _wooAction('import') : null,
                        icon: const Icon(Icons.download),
                        label: Text(context.tr('woo_import')),
                      ),
                      OutlinedButton.icon(
                        onPressed: enabled && !_syncing ? () => _wooAction('push-stock') : null,
                        icon: const Icon(Icons.upload),
                        label: Text(context.tr('woo_push_stock_now')),
                      ),
                      if (_syncing) const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                    ]),
                  ]),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: Text(context.tr('delivery_zones'), style: Theme.of(context).textTheme.titleLarge)),
            FilledButton.icon(onPressed: () => _editZone(), icon: const Icon(Icons.add), label: Text(context.tr('new_zone'))),
          ]),
          const SizedBox(height: 8),
          AsyncBuilder<List<DeliveryZone>>(
            key: ValueKey('zones$_version'),
            load: () async => (await api.get('/admin/zones') as List).whereType<Json>().map(DeliveryZone.fromJson).toList(),
            builder: (context, zones, _) => Column(children: [
              for (final z in zones)
                ListTile(
                  leading: Icon(Icons.place_outlined, color: z.active ? BmColors.primary : BmColors.muted),
                  title: Text(z.name),
                  subtitle: Text('${formatKes(z.fee)} · ${context.tr('eta_minutes', {'n': z.etaMinutes})}'),
                  trailing: z.active ? null : Text(context.tr('disabled')),
                  onTap: () => _editZone(z),
                ),
            ]),
          ),
        ],
      ),
    );
  }
}
