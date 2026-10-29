import 'package:babymama_core/babymama_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'pages/categories_page.dart';
import 'pages/customers_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/drivers_page.dart';
import 'pages/marketing_page.dart';
import 'pages/orders_page.dart';
import 'pages/products_page.dart';
import 'pages/settings_page.dart';
import 'pages/stock_page.dart';
import 'pages/support_page.dart';

class _Section {
  const _Section(this.labelKey, this.icon, this.page, {this.supportAllowed = false});

  final String labelKey;
  final IconData icon;
  final Widget page;
  final bool supportAllowed;
}

const _sections = [
  _Section('admin_dashboard', Icons.dashboard_outlined, DashboardPage()),
  _Section('admin_products', Icons.checkroom_outlined, ProductsPage()),
  _Section('admin_categories', Icons.category_outlined, CategoriesPage()),
  _Section('admin_stock', Icons.inventory_2_outlined, StockPage()),
  _Section('admin_orders', Icons.receipt_long_outlined, OrdersPage()),
  _Section('admin_riders', Icons.delivery_dining_outlined, DriversPage()),
  _Section('admin_marketing', Icons.view_carousel_outlined, MarketingPage()),
  _Section('admin_support', Icons.support_agent, SupportPage(), supportAllowed: true),
  _Section('admin_customers', Icons.people_outline, CustomersPage()),
  _Section('admin_settings', Icons.settings_outlined, SettingsPage()),
];

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final isAdmin = session.user?.isAdmin ?? false;
    final sections = _sections.where((s) => isAdmin || s.supportAllowed).toList();
    final index = _index.clamp(0, sections.length - 1);
    final wide = MediaQuery.sizeOf(context).width >= 1100;

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: wide,
            selectedIndex: index,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: wide ? NavigationRailLabelType.none : NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(children: [
                Text(wide ? 'babymama admin' : 'bm',
                    style: const TextStyle(color: BmColors.primary, fontWeight: FontWeight.w900, fontSize: 18)),
                const SizedBox(height: 8),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  const LanguageMenu(),
                  IconButton(
                    tooltip: context.tr('sign_out'),
                    icon: const Icon(Icons.logout),
                    onPressed: () => session.logout(),
                  ),
                ]),
              ]),
            ),
            destinations: [
              for (final s in sections)
                NavigationRailDestination(icon: Icon(s.icon), label: Text(context.tr(s.labelKey))),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: sections[index].page),
        ],
      ),
    );
  }
}
