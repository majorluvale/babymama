import 'package:babymama_core/babymama_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../widgets.dart';

/// Settings > Sign-in by SMS: Africa's Talking keys, saved in the database (API key encrypted) and used
/// at once, without redeploying. The key is never sent back: the page only shows whether it is set.
class SmsSettingsPage extends StatefulWidget {
  const SmsSettingsPage({super.key});

  @override
  State<SmsSettingsPage> createState() => _SmsSettingsPageState();
}

class _SmsSettingsPageState extends State<SmsSettingsPage> {
  Json? _data;
  String? _error;
  bool _saving = false;

  final _senderId = TextEditingController();
  final _username = TextEditingController();
  final _apiKey = TextEditingController();
  bool _clearApiKey = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_senderId, _username, _apiKey]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await context.read<ApiClient>().get('/admin/settings/sms') as Json;
      if (!mounted) return;
      setState(() {
        _data = data;
        _error = null;
        _clearApiKey = false;
        _apiKey.clear();
        _senderId.text = '${data['senderId'] ?? ''}';
        _username.text = '${(data['africasTalking'] as Json?)?['username'] ?? ''}';
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _save() async {
    final at = <String, dynamic>{'username': _username.text.trim()};
    if (_apiKey.text.trim().isNotEmpty) {
      at['apiKey'] = _apiKey.text.trim();
    } else if (_clearApiKey) {
      at['apiKey'] = '';
    }
    final body = {'mock': _data!['mock'], 'senderId': _senderId.text.trim(), 'africasTalking': at};
    setState(() => _saving = true);
    final ok = await runApi(context, () => context.read<ApiClient>().put('/admin/settings/sms', body), success: context.tr('saved'));
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) _load();
  }

  Future<void> _test() async {
    try {
      final res = await context.read<ApiClient>().post('/admin/settings/sms/test') as Json;
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
    final apiKeySet = (_data?['africasTalking'] as Json?)?['apiKeySet'] == true;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('sms_settings'), style: const TextStyle(fontWeight: FontWeight.w800)),
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
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        Text(context.tr('sms_settings_summary'), style: const TextStyle(color: BmColors.muted)),
                        const SizedBox(height: 16),
                        Card(
                          elevation: 0,
                          color: BmColors.surface,
                          child: SwitchListTile(
                            value: _data!['mock'] == true,
                            onChanged: (v) => setState(() => _data!['mock'] = v),
                            title: Text(context.tr('sms_simulation')),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _senderId,
                          decoration: InputDecoration(labelText: context.tr('sms_sender_id')),
                        ),
                        const SizedBox(height: 20),
                        Text(context.tr('sms_provider_at'), style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text(context.tr('sms_at_help'), style: const TextStyle(color: BmColors.muted, fontSize: 13)),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _username,
                          decoration: InputDecoration(labelText: context.tr('sms_at_username')),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _apiKey,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: context.tr('sms_at_api_key'),
                            hintText: apiKeySet && !_clearApiKey ? context.tr('secret_saved_hint') : null,
                            suffixIcon: apiKeySet
                                ? IconButton(
                                    tooltip: context.tr('remove'),
                                    icon: Icon(_clearApiKey ? Icons.undo : Icons.delete_outline),
                                    onPressed: () => setState(() => _clearApiKey = !_clearApiKey),
                                  )
                                : null,
                          ),
                        ),
                        if (_clearApiKey)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(context.tr('secret_will_be_removed'), style: const TextStyle(color: BmColors.danger, fontSize: 12)),
                          ),
                        const SizedBox(height: 20),
                        OutlinedButton.icon(
                          onPressed: _test,
                          icon: const Icon(Icons.wifi_tethering),
                          label: Text(context.tr('payment_test_connection')),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }
}
