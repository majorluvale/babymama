import 'package:babymama_core/babymama_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../widgets.dart';

const _ticketStatuses = ['OPEN', 'PENDING', 'RESOLVED', 'CLOSED'];

class SupportPage extends StatefulWidget {
  const SupportPage({super.key});

  @override
  State<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends State<SupportPage> {
  String? _status = 'OPEN';
  int _version = 0;

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    return Scaffold(
      appBar: PageHeader(
        title: context.tr('admin_support'),
        actions: [IconButton(onPressed: () => setState(() => _version++), icon: const Icon(Icons.refresh))],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Wrap(spacing: 8, children: [
            ChoiceChip(label: Text(context.tr('all')), selected: _status == null, onSelected: (_) => setState(() => _status = null)),
            for (final s in _ticketStatuses)
              ChoiceChip(label: Text(context.tr('ticket_status_$s')), selected: _status == s, onSelected: (_) => setState(() => _status = s)),
          ]),
        ),
        Expanded(
          child: AsyncBuilder<List<SupportTicket>>(
            key: ValueKey('$_status|$_version'),
            load: () async => (await api.get('/admin/support', query: {'status': _status}) as List)
                .whereType<Json>()
                .map(SupportTicket.fromJson)
                .toList(),
            builder: (context, tickets, reload) {
              if (tickets.isEmpty) return EmptyView(icon: Icons.forum_outlined, message: context.tr('no_tickets'));
              return ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: tickets.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final t = tickets[i];
                  return ListTile(
                    title: Text(t.subject),
                    subtitle: Text([
                      t.user?.name ?? '',
                      if (t.orderNumber != null) t.orderNumber!,
                      formatDateTime(t.updatedAt),
                      t.lastMessage ?? '',
                    ].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      StatusChip(t.status, prefix: 'ticket_status_'),
                      PopupMenuButton<String>(
                        onSelected: (s) async {
                          if (await runApi(context, () => api.patch('/admin/support/${t.id}', {'status': s}))) reload();
                        },
                        itemBuilder: (ctx) => [
                          for (final s in _ticketStatuses) PopupMenuItem(value: s, child: Text(ctx.tr('ticket_status_$s'))),
                        ],
                      ),
                    ]),
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => TicketChatScreen(ticketId: t.id, staff: true)),
                      );
                      reload();
                    },
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}
