import 'package:babymama_core/babymama_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../widgets/site_layout.dart';

/// Sign in with a phone number: request a code by SMS, then enter it. Pops `true` once signed in.
class PhoneAuthScreen extends StatefulWidget {
  const PhoneAuthScreen({super.key});

  @override
  State<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends State<PhoneAuthScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _name = TextEditingController();
  bool _busy = false;
  bool _codeSent = false;
  String? _devCode;

  @override
  void dispose() {
    for (final c in [_phone, _code, _name]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _sendCode() {
    if (_phone.text.trim().length < 9) {
      showSnack(context, context.tr('invalid_phone'), error: true);
      return;
    }
    final session = context.read<Session>();
    final lang = context.lang;
    _run(() async {
      final dev = await session.requestPhoneCode(_phone.text, locale: lang);
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _devCode = dev;
      });
    });
  }

  void _verify() {
    if (!RegExp(r'^\d{6}$').hasMatch(_code.text.trim())) {
      showSnack(context, context.tr('phone_enter_code'), error: true);
      return;
    }
    final session = context.read<Session>();
    final lang = context.lang;
    _run(() async {
      await session.verifyPhoneCode(_phone.text, _code.text, name: _name.text, locale: lang);
      if (mounted) Navigator.of(context).pop(true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SiteScaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.sms_outlined, size: 40, color: BmColors.primary),
                const SizedBox(height: 12),
                Text(context.tr('phone_sign_in_title'),
                    textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 20),
                if (!_codeSent) ..._requestStep(context) else ..._verifyStep(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _requestStep(BuildContext context) => [
        Text(context.tr('phone_enter_number'), textAlign: TextAlign.center, style: const TextStyle(color: BmColors.muted)),
        const SizedBox(height: 16),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          autofillHints: const [AutofillHints.telephoneNumber],
          decoration: InputDecoration(labelText: context.tr('phone'), hintText: '07XX XXX XXX'),
          onSubmitted: (_) => _sendCode(),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _sendCode,
          child: _busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(context.tr('phone_send_code')),
        ),
      ];

  List<Widget> _verifyStep(BuildContext context) => [
        Text(context.tr('phone_code_sent', {'phone': _phone.text.trim()}),
            textAlign: TextAlign.center, style: const TextStyle(color: BmColors.muted)),
        if (_devCode != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: BmColors.surface, borderRadius: BorderRadius.circular(8)),
            child: Text(context.tr('phone_dev_code', {'code': _devCode!}),
                textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
        const SizedBox(height: 16),
        TextField(
          controller: _code,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.w700),
          decoration: InputDecoration(labelText: context.tr('phone_enter_code')),
          onSubmitted: (_) => _verify(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: context.tr('full_name')),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _verify,
          child: _busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(context.tr('phone_verify')),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(onPressed: _busy ? null : () => setState(() => _codeSent = false), child: Text(context.tr('phone_change_number'))),
            TextButton(onPressed: _busy ? null : _sendCode, child: Text(context.tr('phone_resend'))),
          ],
        ),
      ];
}
