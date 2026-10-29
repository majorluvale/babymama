import 'dart:async';

import 'package:babymama_core/babymama_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../widgets/shop_widgets.dart';
import '../widgets/site_layout.dart';
import 'checkout_screen.dart';
import 'orders_screen.dart';

/// Mobile money (M-Pesa / Airtel Money STK push) or card payment, then polling until confirmed.
class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key, required this.order});

  final Order order;

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  late String _method = widget.order.paymentMethod == 'CASH_ON_DELIVERY' ? 'MPESA' : widget.order.paymentMethod;
  late final _phone = TextEditingController(text: widget.order.phone);
  List<PaymentOption> _methods = [];
  PaymentAttempt? _attempt;
  Timer? _poll;
  DateTime? _pollStarted;
  bool _busy = false;
  String? _error;

  ApiClient get _api => context.read<ApiClient>();

  @override
  void initState() {
    super.initState();
    _api.get('/payments/methods').then((list) {
      if (!mounted) return;
      setState(() {
        _methods = (list as List)
            .whereType<Json>()
            .map(PaymentOption.fromJson)
            .where((m) => m.method != 'CASH_ON_DELIVERY')
            .toList();
      });
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _poll?.cancel();
    _phone.dispose();
    super.dispose();
  }

  bool get _waiting => _poll?.isActive ?? false;

  Future<void> _pay() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final attempt = PaymentAttempt.fromJson(await _api.post('/payments/orders/${widget.order.id}', {
        'method': _method,
        if (_method != 'CARD') 'phone': _phone.text.trim(),
      }) as Json);
      if (!mounted) return;
      setState(() => _attempt = attempt);
      if (attempt.status == 'FAILED') {
        setState(() => _error = attempt.message ?? context.tr('payment_failed'));
        return;
      }
      if (attempt.redirectUrl != null) await openExternal(attempt.redirectUrl!);
      _startPolling();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startPolling() {
    _poll?.cancel();
    _pollStarted = DateTime.now();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _check());
    setState(() {});
  }

  Future<void> _check() async {
    final attempt = _attempt;
    if (attempt == null || !mounted) return;
    if (DateTime.now().difference(_pollStarted!) > const Duration(minutes: 3)) {
      _poll?.cancel();
      setState(() => _error = context.tr('payment_timeout'));
      return;
    }
    try {
      final latest = PaymentAttempt.fromJson(await _api.get('/payments/${attempt.id}') as Json);
      if (!mounted) return;
      if (latest.status == 'SUCCESS') {
        _poll?.cancel();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: widget.order.id, justPlaced: true)),
        );
      } else if (latest.status == 'FAILED') {
        _poll?.cancel();
        setState(() => _error = latest.message ?? context.tr('payment_failed'));
      }
    } on ApiException {
      // Keep polling on transient errors.
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final mobileMoney = _method != 'CARD';
    return SiteScaffold(
      title: context.tr('payment'),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(context.tr('order_n', {'n': order.number}), style: const TextStyle(color: BmColors.muted)),
              const SizedBox(height: 4),
              Text(formatKes(order.total), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
              if (order.expiresAt != null)
                Text(context.tr('reserved_until', {'time': formatTime(order.expiresAt!)}),
                    style: const TextStyle(color: BmColors.warning)),
              const SizedBox(height: 20),
              Wrap(spacing: 8, children: [
                for (final m in _methods)
                  ChoiceChip(
                    avatar: Icon(paymentIcon(m.method), size: 18),
                    label: Text(context.tr('pay_${m.method}')),
                    selected: _method == m.method,
                    onSelected: _waiting ? null : (_) => setState(() => _method = m.method),
                  ),
              ]),
              const SizedBox(height: 16),
              if (mobileMoney)
                TextField(
                  controller: _phone,
                  enabled: !_waiting,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: context.tr(_method == 'MPESA' ? 'mpesa_number' : 'airtel_number'),
                    hintText: '07XX XXX XXX',
                    prefixIcon: const Icon(Icons.phone_android),
                  ),
                ),
              const SizedBox(height: 20),
              if (_waiting)
                Card(
                  elevation: 0,
                  color: BmColors.surface,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        mobileMoney ? context.tr('stk_instructions') : context.tr('card_instructions'),
                        textAlign: TextAlign.center,
                      ),
                      if (_attempt?.redirectUrl != null)
                        TextButton(onPressed: () => openExternal(_attempt!.redirectUrl!), child: Text(context.tr('open_payment_page'))),
                    ]),
                  ),
                )
              else
                FilledButton(
                  onPressed: _busy ? null : _pay,
                  child: _busy
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(context.tr('pay_amount', {'amount': formatKes(order.total)})),
                ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: BmColors.danger)),
              ],
              const SizedBox(height: 24),
              TextButton(
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: order.id)),
                ),
                child: Text(context.tr('view_order')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
