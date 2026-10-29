import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api_client.dart';
import '../i18n.dart';
import '../session.dart';
import '../theme.dart';
import 'common.dart';

/// E-mail / password sign-in used by the rider app and the admin back-office.
class StaffLoginScreen extends StatefulWidget {
  const StaffLoginScreen({super.key, required this.title, required this.allowedRoles, this.icon = Icons.lock_outline});

  final String title;
  final List<String> allowedRoles;
  final IconData icon;

  @override
  State<StaffLoginScreen> createState() => _StaffLoginScreenState();
}

class _StaffLoginScreenState extends State<StaffLoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final session = context.read<Session>();
    setState(() => _busy = true);
    try {
      await session.login(_email.text, _password.text);
      if (!widget.allowedRoles.contains(session.user?.role)) {
        await session.logout();
        if (mounted) showSnack(context, context.tr('wrong_app_role'), error: true);
      }
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(actions: const [LanguageMenu()]),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(widget.icon, size: 56, color: BmColors.primary),
                  const SizedBox(height: 12),
                  Text(widget.title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 28),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: InputDecoration(labelText: context.tr('email')),
                    validator: (v) => (v ?? '').contains('@') ? null : context.tr('invalid_email'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.password],
                    onFieldSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: context.tr('password'),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) => (v ?? '').isEmpty ? context.tr('required') : null,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(context.tr('sign_in')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
