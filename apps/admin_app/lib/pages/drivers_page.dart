import 'package:babymama_core/babymama_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../widgets.dart';

class DriversPage extends StatefulWidget {
  const DriversPage({super.key});

  @override
  State<DriversPage> createState() => _DriversPageState();
}

class _DriversPageState extends State<DriversPage> {
  int _version = 0;

  Future<void> _addStaff() async {
    final name = TextEditingController();
    final email = TextEditingController();
    final phone = TextEditingController();
    final password = TextEditingController();
    final plate = TextEditingController();
    var role = 'DRIVER';
    var vehicle = 'MOTORBIKE';
    final api = context.read<ApiClient>();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(ctx.tr('add_staff')),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: InputDecoration(labelText: ctx.tr('role')),
                  items: [for (final r in ['DRIVER', 'SUPPORT', 'ADMIN']) DropdownMenuItem(value: r, child: Text(ctx.tr('role_$r')))],
                  onChanged: (v) => setState(() => role = v ?? 'DRIVER'),
                ),
                const SizedBox(height: 8),
                TextField(controller: name, decoration: InputDecoration(labelText: ctx.tr('full_name'))),
                const SizedBox(height: 8),
                TextField(controller: email, decoration: InputDecoration(labelText: ctx.tr('email'))),
                const SizedBox(height: 8),
                TextField(controller: phone, decoration: InputDecoration(labelText: ctx.tr('phone'))),
                const SizedBox(height: 8),
                TextField(controller: password, decoration: InputDecoration(labelText: ctx.tr('password'), helperText: ctx.tr('password_rule'))),
                if (role == 'DRIVER') ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: vehicle,
                    decoration: InputDecoration(labelText: ctx.tr('vehicle')),
                    items: [
                      for (final v in ['MOTORBIKE', 'BICYCLE', 'CAR', 'FOOT']) DropdownMenuItem(value: v, child: Text(ctx.tr('vehicle_$v'))),
                    ],
                    onChanged: (v) => setState(() => vehicle = v ?? 'MOTORBIKE'),
                  ),
                  const SizedBox(height: 8),
                  TextField(controller: plate, decoration: InputDecoration(labelText: ctx.tr('plate_number'))),
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('save'))),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final saved = await runApi(
      context,
      () => api.post('/admin/staff', {
        'name': name.text.trim(),
        'email': email.text.trim(),
        if (phone.text.trim().isNotEmpty) 'phone': phone.text.trim(),
        'password': password.text,
        'role': role,
        'vehicleType': vehicle,
        if (plate.text.trim().isNotEmpty) 'plateNumber': plate.text.trim(),
      }),
      success: context.tr('saved'),
    );
    if (saved) setState(() => _version++);
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    return Scaffold(
      appBar: PageHeader(
        title: context.tr('admin_riders'),
        actions: [
          IconButton(onPressed: () => setState(() => _version++), icon: const Icon(Icons.refresh)),
          FilledButton.icon(onPressed: _addStaff, icon: const Icon(Icons.person_add_alt), label: Text(context.tr('add_staff'))),
        ],
      ),
      body: AsyncBuilder<List<Json>>(
        key: ValueKey(_version),
        load: () async => (await api.get('/admin/drivers') as List).whereType<Json>().toList(),
        builder: (context, drivers, reload) {
          if (drivers.isEmpty) return EmptyView(icon: Icons.delivery_dining, message: context.tr('no_riders'));
          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: drivers.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final d = drivers[i];
              final profile = (d['profile'] as Json?) ?? const {};
              final online = profile['isOnline'] == true;
              final lastSeen = DateTime.tryParse('${profile['lastSeenAt']}')?.toLocal();
              return ListTile(
                leading: Badge(
                  backgroundColor: online ? BmColors.success : BmColors.muted,
                  smallSize: 12,
                  child: const CircleAvatar(child: Icon(Icons.delivery_dining)),
                ),
                title: Text('${d['name']}${d['isActive'] == false ? ' (${context.tr('disabled')})' : ''}'),
                subtitle: Text([
                  '${d['phone'] ?? d['email']}',
                  context.tr('vehicle_${profile['vehicleType'] ?? 'MOTORBIKE'}'),
                  if (profile['plateNumber'] != null) '${profile['plateNumber']}',
                  if (lastSeen != null) '${context.tr('last_seen')} ${formatDateTime(lastSeen)}',
                ].join(' · ')),
                trailing: Wrap(spacing: 16, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text('${context.tr('active')}: ${d['activeDeliveries']}'),
                  Text('${context.tr('delivered')}: ${d['deliveredCount']}'),
                  if (d['rating'] != null) Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.star, size: 16, color: Color(0xFFF5A623)), Text('${d['rating']}')]),
                  if (profile['lastLat'] != null)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.place_outlined, size: 14, color: BmColors.muted),
                      Text('${(profile['lastLat'] as num).toStringAsFixed(4)}, ${(profile['lastLng'] as num).toStringAsFixed(4)}',
                          style: const TextStyle(fontSize: 12, color: BmColors.muted)),
                    ]),
                ]),
              );
            },
          );
        },
      ),
    );
  }
}
