import 'package:babymama_core/babymama_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// One delivery: customer contact, navigation, and the accept → pick up → on the way → delivered flow.
class DeliveryScreen extends StatefulWidget {
  const DeliveryScreen({super.key, required this.deliveryId});

  final String deliveryId;

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen> {
  DriverDelivery? _delivery;
  String? _error;
  bool _busy = false;

  ApiClient get _api => context.read<ApiClient>();
  String get _base => '/driver/deliveries/${widget.deliveryId}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = DriverDelivery.fromJson(await _api.get(_base) as Json);
      if (mounted) setState(() => _delivery = d);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _action(String path, [Json? body]) async {
    setState(() => _busy = true);
    try {
      final d = DriverDelivery.fromJson(await _api.post('$_base/$path', body) as Json);
      if (mounted) setState(() => _delivery = d);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  void _navigate(Order o) {
    final query = o.lat != null && o.lng != null
        ? '${o.lat},${o.lng}'
        : Uri.encodeComponent('${o.street}, ${o.landmark ?? ''}, ${o.zoneName}, Nairobi');
    _open('https://www.google.com/maps/dir/?api=1&destination=$query&travelmode=driving');
  }

  Future<void> _complete(Order o) async {
    final code = TextEditingController();
    final cash = TextEditingController(text: o.amountToCollect > 0 ? '${o.amountToCollect}' : '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('confirm_delivery')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(ctx.tr('ask_code')),
          const SizedBox(height: 12),
          TextField(
            controller: code,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 4,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 28, letterSpacing: 8, fontWeight: FontWeight.w800),
          ),
          if (o.amountToCollect > 0)
            TextField(
              controller: cash,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: ctx.tr('cash_collected')),
            ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('confirm'))),
        ],
      ),
    );
    if (ok == true) {
      await _action('complete', {
        'code': code.text.trim(),
        if (o.amountToCollect > 0) 'cashCollected': int.tryParse(cash.text.trim()) ?? o.amountToCollect,
      });
    }
  }

  Future<void> _fail() async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('report_problem')),
        content: TextField(controller: reason, maxLines: 3, decoration: InputDecoration(hintText: ctx.tr('failure_reason_hint'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('submit'))),
        ],
      ),
    );
    if (ok == true && reason.text.trim().length >= 3) await _action('fail', {'reason': reason.text.trim()});
  }

  @override
  Widget build(BuildContext context) {
    final d = _delivery;
    if (d == null) {
      return Scaffold(
        appBar: AppBar(),
        body: _error != null ? ErrorView(message: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator()),
      );
    }
    final o = d.order;
    return Scaffold(
      appBar: AppBar(title: Text(o.number)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(children: [
              Expanded(child: Text(o.zoneName, style: Theme.of(context).textTheme.titleLarge)),
              StatusChip(d.status, prefix: 'delivery_status_'),
            ]),
            const SizedBox(height: 12),
            if (o.amountToCollect > 0)
              Card(
                color: BmColors.warning.withAlpha(30),
                elevation: 0,
                child: ListTile(
                  leading: const Icon(Icons.payments_outlined, color: BmColors.warning),
                  title: Text(context.tr('collect_cash')),
                  trailing: Text(formatKes(o.amountToCollect), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                ),
              )
            else
              Card(
                color: BmColors.success.withAlpha(30),
                elevation: 0,
                child: ListTile(
                  leading: const Icon(Icons.verified_outlined, color: BmColors.success),
                  title: Text(context.tr('already_paid')),
                ),
              ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_outline),
              title: Text(o.recipientName),
              subtitle: Text(o.phone),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(icon: const Icon(Icons.call), onPressed: () => _open('tel:${o.phone}')),
                IconButton(icon: const Icon(Icons.sms_outlined), onPressed: () => _open('sms:${o.phone}')),
              ]),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.place_outlined),
              title: Text(o.street),
              subtitle: Text([if (o.landmark != null) o.landmark!, '${o.zoneName}, Nairobi'].join('\n')),
              trailing: IconButton(icon: const Icon(Icons.navigation_outlined), onPressed: () => _navigate(o)),
            ),
            if (o.notes != null)
              ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.notes), title: Text(o.notes!)),
            const Divider(),
            Text(context.tr('items_count', {'n': o.itemCount}), style: const TextStyle(fontWeight: FontWeight.w700)),
            for (final item in o.items)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: BmImage(item.imageUrl, width: 48, height: 48, radius: 6),
                title: Text(item.title),
                trailing: Text('x${item.quantity}'),
              ),
            if (d.failedReason != null) ...[
              const Divider(),
              Text(d.failedReason!, style: const TextStyle(color: BmColors.danger)),
            ],
            const SizedBox(height: 24),
            ..._actions(d),
          ],
        ),
      ),
    );
  }

  List<Widget> _actions(DriverDelivery d) {
    final o = d.order;
    final disabled = _busy;
    switch (d.status) {
      case 'UNASSIGNED':
      case 'ASSIGNED':
        return [FilledButton(onPressed: disabled ? null : () => _action('accept'), child: Text(context.tr('accept_delivery')))];
      case 'ACCEPTED':
        return [
          FilledButton(
            onPressed: disabled ? null : () => _action('status', {'status': 'PICKED_UP'}),
            child: Text(context.tr('mark_picked_up')),
          ),
          TextButton(onPressed: disabled ? null : _fail, child: Text(context.tr('report_problem'))),
        ];
      case 'PICKED_UP':
      case 'IN_TRANSIT':
        return [
          if (d.status == 'PICKED_UP')
            OutlinedButton(
              onPressed: disabled ? null : () => _action('status', {'status': 'IN_TRANSIT'}),
              child: Text(context.tr('start_trip')),
            ),
          const SizedBox(height: 8),
          FilledButton(onPressed: disabled ? null : () => _complete(o), child: Text(context.tr('mark_delivered'))),
          TextButton(onPressed: disabled ? null : _fail, child: Text(context.tr('report_problem'))),
        ];
      default:
        return const [];
    }
  }
}
