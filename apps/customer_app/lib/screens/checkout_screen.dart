import 'package:babymama_core/babymama_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/cart.dart';
import '../widgets/shop_widgets.dart';
import '../widgets/site_layout.dart';
import 'orders_screen.dart';
import 'payment_screen.dart';

IconData paymentIcon(String method) {
  switch (method) {
    case 'MPESA':
    case 'AIRTEL_MONEY':
      return Icons.phone_android;
    case 'CARD':
      return Icons.credit_card;
    default:
      return Icons.payments_outlined;
  }
}

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _street = TextEditingController();
  final _landmark = TextEditingController();
  final _notes = TextEditingController();

  List<DeliveryZone> _zones = [];
  List<PaymentOption> _methods = [];
  List<Json> _addresses = [];
  DeliveryZone? _zone;
  String? _method;
  bool _saveAddress = true;
  bool _loading = true;
  bool _placing = false;
  String? _error;
  Quote? _quote;

  ApiClient get _api => context.read<ApiClient>();

  @override
  void initState() {
    super.initState();
    final user = context.read<Session>().user;
    _name.text = user?.name ?? '';
    _phone.text = user?.phone ?? '';
    _load();
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _street, _landmark, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _api.get('/zones'),
        _api.get('/payments/methods'),
        _api.get('/auth/me/addresses').catchError((_) => <dynamic>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _zones = (results[0] as List).whereType<Json>().map(DeliveryZone.fromJson).toList();
        _methods = (results[1] as List).whereType<Json>().map(PaymentOption.fromJson).toList();
        _addresses = (results[2] as List).whereType<Json>().toList();
        _method = _methods.isEmpty ? null : _methods.first.method;
        _loading = false;
      });
      if (_addresses.isNotEmpty) _useAddress(_addresses.first);
      _refreshQuote();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _useAddress(Json a) {
    setState(() {
      _name.text = '${a['recipientName'] ?? ''}';
      _phone.text = '${a['phone'] ?? ''}';
      _street.text = '${a['street'] ?? ''}';
      _landmark.text = '${a['landmark'] ?? ''}';
      _saveAddress = false;
      final zoneId = a['zoneId'];
      _zone = _zones.where((z) => z.id == zoneId).firstOrNull ?? _zone;
    });
    _refreshQuote();
  }

  Future<void> _refreshQuote() async {
    final cart = context.read<CartController>();
    try {
      final q = Quote.fromJson(await _api.post('/orders/quote', {...cart.toPayload(), 'zoneId': _zone?.id}) as Json);
      if (mounted) setState(() => _quote = q);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _placeOrder() async {
    if (!_form.currentState!.validate()) return;
    if (_zone == null || _method == null) return;
    final cart = context.read<CartController>();
    setState(() {
      _placing = true;
      _error = null;
    });
    try {
      final res = await _api.post('/orders', {
        ...cart.toPayload(),
        'zoneId': _zone!.id,
        'paymentMethod': _method,
        'address': {
          'recipientName': _name.text.trim(),
          'phone': _phone.text.trim(),
          'street': _street.text.trim(),
          if (_landmark.text.trim().isNotEmpty) 'landmark': _landmark.text.trim(),
        },
        if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
        'saveAddress': _saveAddress,
      }) as Json;
      final order = Order.fromJson(res);
      cart.clear();
      if (!mounted) return;
      final next = order.paymentMethod == 'CASH_ON_DELIVERY'
          ? OrderDetailScreen(orderId: order.id, justPlaced: true)
          : PaymentScreen(order: order);
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => next));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  String? _required(String? v) => (v ?? '').trim().length < 2 ? context.tr('required') : null;

  @override
  Widget build(BuildContext context) {
    return SiteScaffold(
      title: context.tr('checkout'),
      body: _loading && _error == null
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(context.tr('delivery_address'), style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      if (_addresses.isNotEmpty)
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final a in _addresses)
                            ActionChip(
                              avatar: const Icon(Icons.place_outlined, size: 16),
                              label: Text('${a['label']} · ${a['street']}', overflow: TextOverflow.ellipsis),
                              onPressed: () => _useAddress(a),
                            ),
                        ]),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<DeliveryZone>(
                        key: ValueKey(_zone?.id),
                        initialValue: _zone,
                        isExpanded: true,
                        decoration: InputDecoration(labelText: context.tr('delivery_zone')),
                        items: [
                          for (final z in _zones)
                            DropdownMenuItem(value: z, child: Text('${z.name} · ${formatKes(z.fee)}')),
                        ],
                        validator: (v) => v == null ? context.tr('required') : null,
                        onChanged: (z) {
                          setState(() => _zone = z);
                          _refreshQuote();
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(controller: _name, decoration: InputDecoration(labelText: context.tr('recipient_name')), validator: _required),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(labelText: context.tr('phone'), hintText: '07XX XXX XXX'),
                        validator: (v) => RegExp(r'^\+?\d{9,13}$').hasMatch((v ?? '').replaceAll(' ', '')) ? null : context.tr('invalid_phone'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _street,
                        decoration: InputDecoration(labelText: context.tr('street'), hintText: context.tr('street_hint')),
                        validator: _required,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _landmark,
                        decoration: InputDecoration(labelText: context.tr('landmark'), hintText: context.tr('landmark_hint')),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _notes,
                        maxLines: 2,
                        decoration: InputDecoration(labelText: context.tr('order_notes')),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _saveAddress,
                        onChanged: (v) => setState(() => _saveAddress = v ?? false),
                        title: Text(context.tr('save_address')),
                      ),
                      const SizedBox(height: 8),
                      Text(context.tr('payment_method'), style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      for (final m in _methods)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(paymentIcon(m.method), color: BmColors.primary),
                          title: Text(context.tr('pay_${m.method}')),
                          subtitle: m.simulated ? Text(context.tr('test_mode')) : null,
                          trailing: Icon(_method == m.method ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                              color: _method == m.method ? BmColors.primary : BmColors.muted),
                          onTap: () => setState(() => _method = m.method),
                        ),
                      const Divider(height: 32),
                      if (_quote != null) ...[
                        KeyValueRow(context.tr('subtotal'), formatKes(_quote!.subtotal)),
                        if (_quote!.discount > 0)
                          KeyValueRow(context.tr('multibuy_discount', {'p': _quote!.discountPercent}), '-${formatKes(_quote!.discount)}',
                              color: BmColors.success),
                        KeyValueRow(context.tr('delivery'), _zone == null ? '-' : formatKes(_quote!.deliveryFee)),
                        KeyValueRow(context.tr('total'), formatKes(_quote!.total), bold: true),
                        if (_zone != null)
                          Text(context.tr('eta_minutes', {'n': _zone!.etaMinutes}), style: const TextStyle(color: BmColors.muted)),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!, style: const TextStyle(color: BmColors.danger)),
                      ],
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _placing || _methods.isEmpty ? null : _placeOrder,
                        child: _placing
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : Text(context.tr('place_order')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
