import 'package:babymama_core/babymama_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/google_auth.dart';
import '../widgets/site_layout.dart';

/// Sign in / create an account, with e-mail or Google. Pops `true` once signed in.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<bool> Function() action) async {
    setState(() => _busy = true);
    try {
      final ok = await action();
      if (ok && mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } catch (e) {
      if (mounted) showSnack(context, context.tr('google_failed'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    final session = context.read<Session>();
    final lang = context.lang;
    _run(() async {
      if (_register) {
        await session.register(
          name: _name.text,
          email: _email.text,
          password: _password.text,
          phone: _phone.text,
          locale: lang,
        );
      } else {
        await session.login(_email.text, _password.text);
      }
      return true;
    });
  }

  void _google() {
    final session = context.read<Session>();
    final lang = context.lang;
    _run(() => signInWithGoogle(session, lang));
  }

  @override
  Widget build(BuildContext context) {
    return SiteScaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('babymama',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: BmColors.primary, fontWeight: FontWeight.w900, fontSize: 32)),
                  const SizedBox(height: 8),
                  Text(_register ? context.tr('create_account') : context.tr('welcome_back'),
                      textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _google,
                    icon: const Text('G', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF4285F4))),
                    label: Text(context.tr('continue_google')),
                  ),
                  const SizedBox(height: 16),
                  Row(children: [
                    const Expanded(child: Divider()),
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text(context.tr('or'))),
                    const Expanded(child: Divider()),
                  ]),
                  const SizedBox(height: 16),
                  if (_register) ...[
                    TextFormField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(labelText: context.tr('full_name')),
                      validator: (v) => (v ?? '').trim().length < 2 ? context.tr('required') : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(labelText: context.tr('phone'), hintText: '07XX XXX XXX'),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: InputDecoration(labelText: context.tr('email')),
                    validator: (v) => RegExp(r'^\S+@\S+\.\S+$').hasMatch((v ?? '').trim()) ? null : context.tr('invalid_email'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscure,
                    autofillHints: [_register ? AutofillHints.newPassword : AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: context.tr('password'),
                      helperText: _register ? context.tr('password_rule') : null,
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    onFieldSubmitted: (_) => _submit(),
                    validator: (v) => (v ?? '').length < (_register ? 8 : 1) ? context.tr('password_rule') : null,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_register ? context.tr('create_account') : context.tr('sign_in')),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => setState(() => _register = !_register),
                    child: Text(_register ? context.tr('have_account') : context.tr('no_account')),
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
