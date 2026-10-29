import 'package:babymama_core/babymama_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../widgets.dart';

const _roles = ['CUSTOMER', 'DRIVER', 'SUPPORT', 'ADMIN'];

class CustomersPage extends StatelessWidget {
  const CustomersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: PageHeader(
          title: context.tr('admin_customers'),
          bottom: TabBar(tabs: [Tab(text: context.tr('users')), Tab(text: context.tr('reviews'))]),
        ),
        body: const TabBarView(children: [_UsersTab(), _ReviewsTab()]),
      ),
    );
  }
}

class _UsersTab extends StatefulWidget {
  const _UsersTab();

  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  final _search = TextEditingController();
  String? _role;
  int _page = 1;
  int _version = 0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    final me = context.read<Session>().user?.id;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: _search,
              decoration: InputDecoration(hintText: context.tr('search_users'), prefixIcon: const Icon(Icons.search)),
              onSubmitted: (_) => setState(() {
                _page = 1;
                _version++;
              }),
            ),
          ),
          const SizedBox(width: 12),
          DropdownButton<String?>(
            value: _role,
            items: [
              DropdownMenuItem<String?>(value: null, child: Text(context.tr('all'))),
              for (final r in _roles) DropdownMenuItem<String?>(value: r, child: Text(context.tr('role_$r'))),
            ],
            onChanged: (v) => setState(() {
              _role = v;
              _page = 1;
            }),
          ),
        ]),
        Expanded(
          child: AsyncBuilder<Paged<BmUser>>(
            key: ValueKey('$_role|$_page|$_version'),
            load: () async => Paged.fromJson(
              await api.get('/admin/users', query: {'role': _role, 'q': _search.text.trim(), 'page': _page, 'pageSize': 30}) as Json,
              BmUser.fromJson,
            ),
            builder: (context, page, reload) => Column(children: [
              Expanded(
                child: ListView.separated(
                  itemCount: page.items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final u = page.items[i];
                    return ListTile(
                      leading: CircleAvatar(child: Text(u.initials)),
                      title: Text(u.name),
                      subtitle: Text([u.email, if (u.phone != null) u.phone!, '${context.tr('orders')}: ${u.orderCount ?? 0}'].join(' · ')),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        DropdownButton<String>(
                          value: u.role,
                          underline: const SizedBox.shrink(),
                          items: [for (final r in _roles) DropdownMenuItem(value: r, child: Text(context.tr('role_$r')))],
                          onChanged: u.id == me
                              ? null
                              : (r) async {
                                  if (r == null || r == u.role) return;
                                  if (await runApi(context, () => api.patch('/admin/users/${u.id}', {'role': r}))) reload();
                                },
                        ),
                        const SizedBox(width: 12),
                        Tooltip(
                          message: context.tr('active'),
                          child: Switch(
                            value: u.isActive,
                            onChanged: u.id == me
                                ? null
                                : (v) async {
                                    if (await runApi(context, () => api.patch('/admin/users/${u.id}', {'isActive': v}))) reload();
                                  },
                          ),
                        ),
                      ]),
                    );
                  },
                ),
              ),
              Pager(page: page.page, pages: page.pages, total: page.total, onPage: (p) => setState(() => _page = p)),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _ReviewsTab extends StatelessWidget {
  const _ReviewsTab();

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    return AsyncBuilder<Json>(
      load: () async => await api.get('/admin/reviews', query: {'pageSize': 100}) as Json,
      builder: (context, res, _) {
        final items = ((res['items'] as List?) ?? const []).whereType<Json>().toList();
        final avg = (res['averageRating'] as num?)?.toDouble();
        final avgDriver = (res['averageDriverRating'] as num?)?.toDouble();
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Wrap(spacing: 12, children: [
              StatCard(label: context.tr('avg_order_rating'), value: avg?.toStringAsFixed(1) ?? '-', icon: Icons.star_outline),
              StatCard(label: context.tr('avg_rider_rating'), value: avgDriver?.toStringAsFixed(1) ?? '-', icon: Icons.delivery_dining),
              StatCard(label: context.tr('reviews'), value: '${res['total'] ?? 0}', icon: Icons.reviews_outlined),
            ]),
            const SizedBox(height: 16),
            if (items.isEmpty) EmptyView(icon: Icons.reviews_outlined, message: context.tr('no_reviews')),
            for (final r in items)
              ListTile(
                leading: RatingStars(rating: (r['rating'] as num?) ?? 0),
                title: Text('${r['customerName']} · ${r['orderNumber']}'),
                subtitle: Text('${r['comment'] ?? ''}'),
                trailing: r['driverRating'] != null ? Text('${context.tr('rider')}: ${r['driverRating']}/5') : null,
              ),
          ],
        );
      },
    );
  }
}
