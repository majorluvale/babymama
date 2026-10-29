import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api_client.dart';
import '../format.dart';
import '../i18n.dart';
import '../models.dart';
import '../theme.dart';
import 'common.dart';

/// Chat-like conversation with the support team, refreshed every 10 seconds.
class TicketChatScreen extends StatefulWidget {
  const TicketChatScreen({super.key, required this.ticketId, this.staff = false});

  final String ticketId;

  /// When true, uses the staff endpoints (admin app).
  final bool staff;

  @override
  State<TicketChatScreen> createState() => _TicketChatScreenState();
}

class _TicketChatScreenState extends State<TicketChatScreen> {
  SupportTicket? _ticket;
  String? _error;
  Timer? _timer;
  final _input = TextEditingController();
  bool _sending = false;

  String get _base => widget.staff ? '/admin/support/${widget.ticketId}' : '/support/${widget.ticketId}';

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final t = SupportTicket.fromJson(await context.read<ApiClient>().get(_base) as Json);
      if (mounted) setState(() => _ticket = t);
    } on ApiException catch (e) {
      if (mounted && _ticket == null) setState(() => _error = e.message);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      final t = SupportTicket.fromJson(await context.read<ApiClient>().post('$_base/messages', {'body': text}) as Json);
      _input.clear();
      if (mounted) setState(() => _ticket = t);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _ticket;
    return Scaffold(
      appBar: AppBar(title: Text(t?.subject ?? context.tr('support'))),
      body: t == null
          ? (_error != null ? ErrorView(message: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator()))
          : Column(
              children: [
                if (t.orderNumber != null)
                  Container(
                    width: double.infinity,
                    color: BmColors.surface,
                    padding: const EdgeInsets.all(8),
                    child: Text('${context.tr('about_order')} ${t.orderNumber}', textAlign: TextAlign.center),
                  ),
                Expanded(
                  child: ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(12),
                    itemCount: t.messages.length,
                    itemBuilder: (context, i) {
                      final m = t.messages[t.messages.length - 1 - i];
                      final mine = widget.staff ? m.isStaff : !m.isStaff;
                      return Align(
                        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 420),
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: mine ? BmColors.primary : BmColors.surface,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!mine)
                                Text(m.isStaff ? 'Babymama · ${m.senderName}' : m.senderName,
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: BmColors.muted)),
                              Text(m.body, style: TextStyle(color: mine ? Colors.white : BmColors.ink)),
                              const SizedBox(height: 4),
                              Text(formatDateTime(m.createdAt),
                                  style: TextStyle(fontSize: 10, color: mine ? Colors.white70 : BmColors.muted)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _input,
                          minLines: 1,
                          maxLines: 4,
                          decoration: InputDecoration(hintText: context.tr('type_message')),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(onPressed: _sending ? null : _send, icon: const Icon(Icons.send)),
                    ]),
                  ),
                ),
              ],
            ),
    );
  }
}
