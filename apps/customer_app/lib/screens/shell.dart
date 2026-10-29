import 'package:babymama_core/babymama_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/categories.dart';
import 'catalog_screen.dart';
import 'home_screen.dart';
import 'profile_screen.dart';
import 'support_screen.dart';

/// Website: the home page (its header links to everything else). Phones: bottom navigation.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  static const _pages = <Widget>[
    HomeScreen(),
    CatalogScreen(),
    SupportScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    context.read<CategoriesController>().load();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width >= kWideBreakpoint) return const HomeScreen();

    final items = [
      (Icons.home_outlined, Icons.home, context.tr('nav_home')),
      (Icons.grid_view_outlined, Icons.grid_view, context.tr('nav_shop')),
      (Icons.chat_bubble_outline, Icons.chat_bubble, context.tr('nav_support')),
      (Icons.person_outline, Icons.person, context.tr('nav_profile')),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final (icon, selected, label) in items)
            NavigationDestination(icon: Icon(icon), selectedIcon: Icon(selected), label: label),
        ],
      ),
    );
  }
}
