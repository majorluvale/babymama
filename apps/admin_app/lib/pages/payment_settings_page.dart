import 'package:babymama_core/babymama_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../widgets.dart';

/// Settings > Payment methods: M-Pesa, Airtel Money and card keys, saved in the database (secrets encrypted)
/// and used at once, without redeploying. Secrets are never sent back: the page only shows whether they are set.
class PaymentSettingsPage extends StatefulWidget {
  const PaymentSettingsPage({super.key});

  @override
  State<PaymentSettingsPage> createState() => _PaymentSettingsPageState();
}

class _PaymentSettingsPageState extends State<PaymentSettingsPage> {
  Json? _data;
  String? _error;
  bool _saving = false;

  /// Plain values edited on the page, per provider ('mpesa.shortcode' -> '174379').
  final Map<String, TextEditingController> _text = {};

  /// Secrets typed on the page; a key present with '' means "remove the saved value".
  final Map<String, TextEditingController> _secrets = {};
  final Set<String> _cleared = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [..._text.values, ..._secrets.values]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await context.read<ApiClient>().get('/admin/settings/payments') as Json;
      if (!mounted) return;
      setState(() {
        _data = data;
        _error = null;
        _cleared.clear();
        for (final c in _secrets.values) {
          c.clear();
        }
        for (final entry in _text.entries) {
          final [group, field] = entry.key.split('.');
          entry.value.text = '${(data[group] as Json?)?[field] ?? ''}';
        }
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Json _section(String group) => (_data![group] as Json?) ?? {};

  TextEditingController _textFor(String group, String field) =>
      _text.putIfAbsent('$group.$field', () => TextEditingController(text: '${_section(group)[field] ?? ''}'));

  TextEditingController _secretFor(String group, String field) => _secrets.putIfAbsent('$group.$field', TextEditingController.new);

  void _set(String group, String field, Object value) => setState(() => _section(group)[field] = value);

  Future<void> _save() async {
    final body = <String, dynamic>{'mock': _data!['mock'], 'cashOnDelivery': _data!['cashOnDelivery']};
    for (final group in ['mpesa', 'airtel', 'flutterwave']) {
      final s = _section(group);
      final out = <String, dynamic>{'enabled': s['enabled']};
      if (s.containsKey('env')) out['env'] = s['env'];
      if (s.containsKey('transactionType')) out['transactionType'] = s['transactionType'];
      _text.forEach((key, c) {
        if (key.startsWith('$group.')) out[key.split('.')[1]] = c.text.trim();
      });
      _secrets.forEach((key, c) {
        if (!key.startsWith('$group.')) return;
        final field = key.split('.')[1];
        if (c.text.trim().isNotEmpty) {
          out[field] = c.text.trim();
        } else if (_cleared.contains(key)) {
          out[field] = '';
        }
      });
      body[group] = out;
    }
    setState(() => _saving = true);
    final ok = await runApi(context, () => context.read<ApiClient>().put('/admin/settings/payments', body), success: context.tr('saved'));
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) _load();
  }

  Future<void> _test(String provider) async {
    try {
      final res = await context.read<ApiClient>().post('/admin/settings/payments/test/$provider') as Json;
      if (!mounted) return;
      showSnack(
        context,
        res['ok'] == true ? context.tr('payment_test_ok') : context.tr('payment_test_failed', {'message': res['message'] ?? ''}),
        error: res['ok'] != true,
      );
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('payment_methods'), style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          FilledButton(onPressed: _data == null || _saving ? null : _save, child: Text(context.tr('save'))),
          const SizedBox(width: 16),
        ],
      ),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : _data == null
              ? const Center(child: CircularProgressIndicator())
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 860),
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        _infoBox(context.tr('payment_settings_intro')),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          value: _data!['mock'] == true,
                          onChanged: (v) => setState(() => _data!['mock'] = v),
                          title: Text(context.tr('payment_mock_mode')),
                          subtitle: Text(context.tr('payment_mock_mode_help')),
                        ),
                        SwitchListTile(
                          value: _data!['cashOnDelivery'] == true,
                          onChanged: (v) => setState(() => _data!['cashOnDelivery'] = v),
                          title: Text(context.tr('pay_CASH_ON_DELIVERY')),
                        ),
                        const SizedBox(height: 12),
                        _providerCard(
                          group: 'mpesa',
                          title: 'M-Pesa (Safaricom Daraja)',
                          help: context.tr('mpesa_help'),
                          children: [
                            _envSwitch('mpesa'),
                            Row(children: [
                              Expanded(child: _field('mpesa', 'consumerKey', 'Consumer key')),
                              const SizedBox(width: 12),
                              Expanded(child: _secretField('mpesa', 'consumerSecret', 'Consumer secret')),
                            ]),
                            Row(children: [
                              Expanded(child: _field('mpesa', 'shortcode', context.tr('mpesa_shortcode'), digits: true)),
                              const SizedBox(width: 12),
                              Expanded(child: _secretField('mpesa', 'passkey', 'Passkey')),
                            ]),
                            Row(children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: _section('mpesa')['transactionType'] as String?,
                                  decoration: InputDecoration(labelText: context.tr('mpesa_account_type')),
                                  items: [
                                    DropdownMenuItem(value: 'CustomerPayBillOnline', child: Text(context.tr('mpesa_paybill'))),
                                    DropdownMenuItem(value: 'CustomerBuyGoodsOnline', child: Text(context.tr('mpesa_till'))),
                                  ],
                                  onChanged: (v) => _set('mpesa', 'transactionType', v ?? 'CustomerPayBillOnline'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: _field('mpesa', 'partyB', context.tr('mpesa_party_b'), digits: true)),
                            ]),
                            _urlRow(context.tr('callback_url_auto'), _section('mpesa')['callbackUrl'] as String?),
                          ],
                        ),
                        _providerCard(
                          group: 'airtel',
                          title: 'Airtel Money',
                          help: context.tr('airtel_help'),
                          children: [
                            _envSwitch('airtel'),
                            Row(children: [
                              Expanded(child: _field('airtel', 'clientId', 'Client ID')),
                              const SizedBox(width: 12),
                              Expanded(child: _secretField('airtel', 'clientSecret', 'Client secret')),
                            ]),
                            _urlRow(context.tr('callback_url_to_give'), _section('airtel')['callbackUrl'] as String?),
                          ],
                        ),
                        _providerCard(
                          group: 'flutterwave',
                          title: context.tr('pay_CARD'),
                          help: context.tr('flutterwave_help'),
                          children: [
                            Row(children: [
                              Expanded(child: _secretField('flutterwave', 'secretKey', 'Secret key')),
                              const SizedBox(width: 12),
                              Expanded(child: _secretField('flutterwave', 'webhookHash', context.tr('flutterwave_webhook_hash'))),
                            ]),
                            _field('flutterwave', 'redirectUrl', context.tr('flutterwave_redirect_url')),
                            _urlRow(context.tr('webhook_url_to_give'), _section('flutterwave')['webhookUrl'] as String?),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _infoBox(String text) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: BmColors.surface, borderRadius: BorderRadius.circular(8)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline, color: BmColors.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
        ]),
      );

  Widget _providerCard({required String group, required String title, required String help, required List<Widget> children}) {
    final s = _section(group);
    final ready = s['ready'] == true;
    final enabled = s['enabled'] == true;
    final (label, color) = ready
        ? (context.tr('payment_status_live'), BmColors.success)
        : !enabled
            ? (context.tr('payment_status_off'), BmColors.muted)
            : _data!['mock'] == true
                ? (context.tr('payment_status_simulated'), BmColors.warning)
                : (context.tr('payment_status_incomplete'), BmColors.danger);
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: BmColors.line)),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: color.withAlpha(30), borderRadius: BorderRadius.circular(12)),
                child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
              ),
              const SizedBox(width: 8),
              Switch(value: enabled, onChanged: (v) => _set(group, 'enabled', v)),
            ]),
            Text(help, style: const TextStyle(color: BmColors.muted, fontSize: 13)),
            const SizedBox(height: 12),
            for (final c in children) Padding(padding: const EdgeInsets.only(bottom: 12), child: c),
            OutlinedButton.icon(
              onPressed: ready ? () => _test(group) : null,
              icon: const Icon(Icons.wifi_tethering, size: 18),
              label: Text(context.tr('payment_test_connection')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _envSwitch(String group) => Row(children: [
        Text(context.tr('payment_environment')),
        const SizedBox(width: 12),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'sandbox', label: Text(context.tr('payment_env_sandbox'))),
            ButtonSegment(value: 'production', label: Text(context.tr('payment_env_production'))),
          ],
          selected: {(_section(group)['env'] as String?) ?? 'sandbox'},
          onSelectionChanged: (v) => _set(group, 'env', v.first),
        ),
      ]);

  Widget _field(String group, String field, String label, {bool digits = false}) => TextField(
        controller: _textFor(group, field),
        keyboardType: digits ? TextInputType.number : null,
        inputFormatters: digits ? [FilteringTextInputFormatter.digitsOnly] : null,
        decoration: InputDecoration(labelText: label),
      );

  /// Empty with "saved" hint when a value exists; typing replaces it, the trash icon removes it.
  Widget _secretField(String group, String field, String label) {
    final key = '$group.$field';
    final saved = _section(group)['${field}Set'] == true && !_cleared.contains(key);
    return TextField(
      controller: _secretFor(group, field),
      obscureText: true,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: label,
        hintText: saved ? context.tr('secret_saved_hint') : null,
        helperText: saved ? context.tr('secret_saved') : (_cleared.contains(key) ? context.tr('secret_will_be_removed') : null),
        suffixIcon: saved
            ? IconButton(
                tooltip: context.tr('remove'),
                icon: const Icon(Icons.delete_outline),
                onPressed: () => setState(() => _cleared.add(key)),
              )
            : null,
      ),
    );
  }

  Widget _urlRow(String label, String? url) => Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        decoration: BoxDecoration(color: BmColors.surface, borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 12, color: BmColors.muted)),
              SelectableText(url ?? '-', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ]),
          ),
          IconButton(
            tooltip: context.tr('copy'),
            icon: const Icon(Icons.copy, size: 18),
            onPressed: url == null
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: url));
                    showSnack(context, context.tr('copied'));
                  },
          ),
        ]),
      );
}
