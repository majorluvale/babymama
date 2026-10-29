import 'package:babymama_core/babymama_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../widgets/shop_widgets.dart';
import '../widgets/site_layout.dart';
import 'auth_screen.dart';

/// Customer support inbox: tickets with the Babymama team + WhatsApp / phone shortcuts.
class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    return SiteScaffold(
      title: context.tr('support'),
      floatingActionButton: session.isLoggedIn
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NewTicketScreen())),
              icon: const Icon(Icons.edit_outlined),
              label: Text(context.tr('new_message')),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.chat_outlined),
                  label: const Text('WhatsApp'),
                  onPressed: () => openExternal('https://wa.me/${BmConfig.supportWhatsapp}'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.call_outlined),
                  label: Text(context.tr('call_us')),
                  onPressed: () => openExternal('tel:${BmConfig.supportPhone}'),
                ),
              ),
            ]),
          ),
          Expanded(
            child: session.isLoggedIn
                ? const _TicketList()
                : EmptyView(
                    icon: Icons.support_agent,
                    message: context.tr('support_sign_in'),
                    action: FilledButton(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AuthScreen())),
                      child: Text(context.tr('sign_in')),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TicketList extends StatelessWidget {
  const _TicketList();

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    return AsyncBuilder<List<SupportTicket>>(
      load: () async => (await api.get('/support') as List).whereType<Json>().map(SupportTicket.fromJson).toList(),
      builder: (context, tickets, reload) {
        if (tickets.isEmpty) return EmptyView(icon: Icons.forum_outlined, message: context.tr('no_tickets'));
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView.separated(
            itemCount: tickets.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final t = tickets[i];
              return ListTile(
                title: Text(t.subject, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  [if (t.orderNumber != null) t.orderNumber!, t.lastMessage ?? ''].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: StatusChip(t.status, prefix: 'ticket_status_'),
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TicketChatScreen(ticketId: t.id)));
                  reload();
                },
              );
            },
          ),
        );
      },
    );
  }
}

class NewTicketScreen extends StatefulWidget {
  const NewTicketScreen({super.key, this.orderId, this.orderNumber});

  final String? orderId;
  final String? orderNumber;

  @override
  State<NewTicketScreen> createState() => _NewTicketScreenState();
}

class _NewTicketScreenState extends State<NewTicketScreen> {
  final _form = GlobalKey<FormState>();
  late final _subject = TextEditingController(
    text: widget.orderNumber == null ? '' : '${context.tr('about_order')} ${widget.orderNumber}',
  );
  final _message = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    if (!await ensureLoggedIn(context)) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final ticket = SupportTicket.fromJson(await context.read<ApiClient>().post('/support', {
        'subject': _subject.text.trim(),
        'message': _message.text.trim(),
        if (widget.orderId != null) 'orderId': widget.orderId,
      }) as Json);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => TicketChatScreen(ticketId: ticket.id)));
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SiteScaffold(
      title: context.tr('new_message'),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _subject,
              decoration: InputDecoration(labelText: context.tr('subject')),
              validator: (v) => (v ?? '').trim().length < 3 ? context.tr('required') : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _message,
              minLines: 5,
              maxLines: 10,
              decoration: InputDecoration(labelText: context.tr('message'), alignLabelWithHint: true),
              validator: (v) => (v ?? '').trim().isEmpty ? context.tr('required') : null,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _busy ? null : _send, child: Text(context.tr('send'))),
          ],
        ),
      ),
    );
  }
}

