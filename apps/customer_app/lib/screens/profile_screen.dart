import 'package:babymama_core/babymama_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/google_auth.dart';
import '../widgets/shop_widgets.dart';
import '../widgets/site_layout.dart';
import 'auth_screen.dart';
import 'orders_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  void _push(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  Future<void> _editProfile(BuildContext context, BmUser user) async {
    final name = TextEditingController(text: user.name);
    final phone = TextEditingController(text: user.phone ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('edit_profile')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: InputDecoration(labelText: ctx.tr('full_name'))),
          const SizedBox(height: 12),
          TextField(controller: phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: ctx.tr('phone'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('save'))),
        ],
      ),
    );
    if (saved == true && context.mounted) {
      try {
        await context.read<Session>().updateProfile({'name': name.text.trim(), 'phone': phone.text.trim()});
      } on ApiException catch (e) {
        if (context.mounted) showSnack(context, e.message, error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final locale = context.watch<LocaleController>();
    final user = session.user;

    final languageTile = ListTile(
      leading: const Icon(Icons.language),
      title: Text(context.tr('language')),
      trailing: SegmentedButton<String>(
        segments: const [ButtonSegment(value: 'en', label: Text('EN')), ButtonSegment(value: 'fr', label: Text('FR'))],
        selected: {locale.lang},
        onSelectionChanged: (s) {
          locale.setLang(s.first);
          if (session.isLoggedIn) session.updateProfile({'locale': s.first}).catchError((_) {});
        },
      ),
    );

    return SiteScaffold(
      title: context.tr('nav_profile'),
      body: ListView(
        children: [
          if (user == null)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                const Icon(Icons.account_circle_outlined, size: 72, color: BmColors.muted),
                const SizedBox(height: 12),
                Text(context.tr('profile_guest'), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: () => _push(context, const AuthScreen()), child: Text(context.tr('sign_in_or_register'))),
              ]),
            )
          else ...[
            ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: CircleAvatar(
                radius: 28,
                backgroundColor: BmColors.primary,
                backgroundImage: user.avatarUrl != null ? NetworkImage(user.avatarUrl!) : null,
                child: user.avatarUrl == null ? Text(user.initials, style: const TextStyle(color: Colors.white)) : null,
              ),
              title: Text(user.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
              subtitle: Text([user.email, if (user.phone != null) user.phone!].join('\n')),
              trailing: IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _editProfile(context, user)),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: Text(context.tr('my_orders')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _push(context, const OrdersScreen()),
            ),
            ListTile(
              leading: const Icon(Icons.favorite_border),
              title: Text(context.tr('favorites')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _push(context, const FavoritesScreen()),
            ),
          ],
          languageTile,
          ListTile(
            leading: const Icon(Icons.local_shipping_outlined),
            title: Text(context.tr('delivery_info')),
            subtitle: Text(context.tr('delivery_info_sub')),
          ),
          if (user != null)
            ListTile(
              leading: const Icon(Icons.logout, color: BmColors.danger),
              title: Text(context.tr('sign_out'), style: const TextStyle(color: BmColors.danger)),
              onTap: () async {
                await signOutGoogle();
                await session.logout();
              },
            ),
          const SizedBox(height: 24),
          const Center(child: Text('Babymama · Nairobi, Kenya', style: TextStyle(color: BmColors.muted, fontSize: 12))),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    return SiteScaffold(
      title: context.tr('favorites'),
      body: AsyncBuilder<List<Product>>(
        load: () async => (await api.get('/me/favorites') as List).whereType<Json>().map(Product.fromJson).toList(),
        builder: (context, items, reload) {
          if (items.isEmpty) return EmptyView(icon: Icons.favorite_border, message: context.tr('no_favorites'));
          return RefreshIndicator(
            onRefresh: reload,
            child: CustomScrollView(slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
              ProductSliverGrid(products: items),
            ]),
          );
        },
      ),
    );
  }
}
