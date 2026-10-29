import 'dart:math' as math;

import 'package:babymama_core/babymama_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/auth_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/support_screen.dart';
import '../state/categories.dart';
import 'search.dart';
import 'shop_widgets.dart';

/// True when the website layout (header with departments, centred content) is used.
bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= kWideBreakpoint;

/// Side padding that keeps content within [kSiteMaxWidth] and centred.
double siteGutter(double width) => math.max(width < kWideBreakpoint ? 16 : 24, (width - kSiteMaxWidth) / 2);

void goHome(BuildContext context) => Navigator.of(context).popUntil((r) => r.isFirst);

void openAccount(BuildContext context) => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => context.read<Session>().isLoggedIn ? const ProfileScreen() : const AuthScreen(),
    ));

/// Page frame shared by every customer screen.
/// Wide screens: site header, then [body] centred at [kSiteMaxWidth] under an optional page title.
/// Phones: a regular app bar, with the departments under it on shop pages.
/// Pages that manage their own width (home, catalog) pass `fullWidth: true` and use [siteGutter].
class SiteScaffold extends StatelessWidget {
  const SiteScaffold({
    super.key,
    required this.body,
    this.title,
    this.actions = const [],
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.fullWidth = false,
    this.showDepartments = false,
  });

  final Widget body;
  final String? title;

  /// Extra app bar actions on phones (the cart button is always there).
  final List<Widget> actions;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final bool fullWidth;

  /// Phones: department tabs under the app bar.
  final bool showDepartments;

  @override
  Widget build(BuildContext context) {
    if (!isWide(context)) {
      final canPop = Navigator.of(context).canPop();
      return Scaffold(
        appBar: AppBar(
          title: title != null ? Text(title!) : const SiteLogo(size: 22),
          actions: [
            ...actions,
            IconButton(tooltip: context.tr('nav_search'), icon: const Icon(Icons.search), onPressed: () => openSearchPage(context)),
            if (!canPop) const LanguageMenu(),
            const CartButton(),
            const SizedBox(width: 4),
          ],
          bottom: showDepartments ? const PreferredSize(preferredSize: Size.fromHeight(44), child: _DepartmentTabs(compact: true)) : null,
        ),
        body: body,
        bottomNavigationBar: bottomNavigationBar,
        floatingActionButton: floatingActionButton,
      );
    }

    Widget content = body;
    if (!fullWidth) {
      content = LayoutBuilder(builder: (context, constraints) {
        final gutter = siteGutter(constraints.maxWidth);
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null)
                Padding(
                  padding: const EdgeInsets.only(top: 28, bottom: 8),
                  child: Text(title!, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                ),
              Expanded(child: body),
              if (bottomNavigationBar != null) bottomNavigationBar!,
            ],
          ),
        );
      });
    }
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(children: [const SiteHeader(), Expanded(child: content)]),
      floatingActionButton: floatingActionButton,
    );
  }
}

class SiteLogo extends StatelessWidget {
  const SiteLogo({super.key, this.size = 26});

  final double size;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => goHome(context),
      child: Text('babymama', style: TextStyle(color: BmColors.primary, fontWeight: FontWeight.w900, fontSize: size, letterSpacing: -0.5)),
    );
  }
}

/// Website header: logo, search, account / support / language / cart, then the departments.
class SiteHeader extends StatelessWidget {
  const SiteHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final gutter = siteGutter(width);
    final session = context.watch<Session>();
    return Material(
      color: Colors.white,
      child: Container(
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: BmColors.line))),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: BmColors.ink,
              padding: const EdgeInsets.symmetric(vertical: 6),
              alignment: Alignment.center,
              child: Text(context.tr('site_strip'), style: const TextStyle(color: Colors.white, fontSize: 12, letterSpacing: 0.3)),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(gutter, 14, gutter, 6),
              child: Row(
                children: [
                  const SiteLogo(),
                  const SizedBox(width: 40),
                  const Expanded(child: Align(alignment: Alignment.centerLeft, child: SiteSearchField(maxWidth: 520))),
                  const SizedBox(width: 24),
                  _HeaderButton(
                    icon: Icons.chat_bubble_outline,
                    label: context.tr('nav_support'),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SupportScreen())),
                  ),
                  _HeaderButton(
                    icon: Icons.person_outline,
                    label: session.isLoggedIn ? session.user!.name.split(' ').first : context.tr('sign_in'),
                    onTap: () => openAccount(context),
                  ),
                  const LanguageMenu(),
                  const CartButton(),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: gutter),
              child: const Align(alignment: Alignment.centerLeft, child: _DepartmentTabs()),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(foregroundColor: BmColors.ink),
      icon: Icon(icon, size: 20),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

/// WOMEN | MEN | KIDS, then "New in". On the website, hovering a department opens its sub-categories.
class _DepartmentTabs extends StatelessWidget {
  const _DepartmentTabs({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final departments = context.watch<CategoriesController>().departments;
    final style = TextButton.styleFrom(
      foregroundColor: BmColors.ink,
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16, vertical: compact ? 10 : 16),
      textStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: compact ? 13 : 15, letterSpacing: 1.1),
      shape: const RoundedRectangleBorder(),
    );
    final newIn = TextButton(
      style: style,
      onPressed: () => openCatalog(context, sort: 'newest', title: context.tr('new_arrivals')),
      child: Text(context.tr('new_arrivals').toUpperCase()),
    );
    if (compact) {
      return SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          children: [
            for (final d in departments)
              TextButton(
                style: style,
                onPressed: () => openCatalog(context, categoryId: d.id, title: d.name(context.lang)),
                child: Text(d.name(context.lang).toUpperCase()),
              ),
            newIn,
          ],
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final d in departments) _DepartmentMenu(department: d, style: style),
        newIn,
      ],
    );
  }
}

class _DepartmentMenu extends StatefulWidget {
  const _DepartmentMenu({required this.department, required this.style});

  final Category department;
  final ButtonStyle style;

  @override
  State<_DepartmentMenu> createState() => _DepartmentMenuState();
}

class _DepartmentMenuState extends State<_DepartmentMenu> {
  /// Only one department menu is open at a time.
  static _DepartmentMenuState? _open;

  final _controller = MenuController();
  bool _inMenu = false;

  void _show() {
    if (_open != this) _open?._controller.close();
    _open = this;
    _controller.open();
  }

  void _hideSoon() {
    Future.delayed(const Duration(milliseconds: 180), () {
      if (mounted && !_inMenu) _controller.close();
    });
  }

  @override
  void dispose() {
    if (_open == this) _open = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.lang;
    final d = widget.department;
    final children = context.watch<CategoriesController>().childrenOf(d.id);
    void open(Category c) {
      _controller.close();
      openCatalog(context, categoryId: c.id, title: c.path(lang));
    }

    return MenuAnchor(
      controller: _controller,
      style: const MenuStyle(
        backgroundColor: WidgetStatePropertyAll(Colors.white),
        elevation: WidgetStatePropertyAll(6),
        padding: WidgetStatePropertyAll(EdgeInsets.zero),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(6)))),
      ),
      menuChildren: [
        MouseRegion(
          onEnter: (_) => _inMenu = true,
          onExit: (_) {
            _inMenu = false;
            _controller.close();
          },
          // Two columns of icon + name, so long departments stay compact.
          child: Container(
            width: children.length > 6 ? 520 : 280,
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MenuLink(label: context.tr('see_all_in', {'name': d.name(lang)}), icon: d.icon, bold: true, onTap: () => open(d)),
                const Divider(height: 12, indent: 20, endIndent: 20),
                Wrap(
                  children: [
                    for (final c in children)
                      SizedBox(width: children.length > 6 ? 260 : 280, child: _MenuLink(label: c.name(lang), icon: c.icon, onTap: () => open(c))),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
      builder: (context, controller, _) => MouseRegion(
        onEnter: (_) => _show(),
        onExit: (_) => _hideSoon(),
        child: TextButton(
          style: widget.style,
          onPressed: () {
            _controller.close();
            openCatalog(context, categoryId: d.id, title: d.name(lang));
          },
          child: Text(d.name(lang).toUpperCase()),
        ),
      ),
    );
  }
}

class _MenuLink extends StatelessWidget {
  const _MenuLink({required this.label, required this.onTap, this.icon, this.bold = false});

  final String label;
  final VoidCallback onTap;
  final String? icon;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(children: [
          CategoryIcon(icon, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.w700 : FontWeight.w400))),
        ]),
      ),
    );
  }
}

/// Round icon + name, used to browse sub-categories (home page, search panel).
class CategoryChip extends StatelessWidget {
  const CategoryChip({super.key, required this.category, required this.onTap, this.label});

  final Category category;
  final VoidCallback onTap;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
        decoration: BoxDecoration(color: BmColors.surface, borderRadius: BorderRadius.circular(24)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 30,
            height: 30,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: CategoryIcon(category.icon, size: 18),
          ),
          const SizedBox(width: 8),
          Text(label ?? category.name(context.lang), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }
}

/// Website footer, placed at the end of long pages (home, catalog).
class SiteFooter extends StatelessWidget {
  const SiteFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final gutter = siteGutter(width);
    final lang = context.lang;
    final departments = context.watch<CategoriesController>().departments;
    const heading = TextStyle(fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 1);
    Widget link(String label, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: InkWell(onTap: onTap, child: Text(label, style: const TextStyle(color: BmColors.muted))),
        );

    final columns = [
      SizedBox(
        width: 300,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SiteLogo(size: 22),
          const SizedBox(height: 10),
          Text(context.tr('footer_about'), style: const TextStyle(color: BmColors.muted, height: 1.5)),
        ]),
      ),
      SizedBox(
        width: 180,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.tr('footer_shop').toUpperCase(), style: heading),
          for (final d in departments) link(d.name(lang), () => openCatalog(context, categoryId: d.id, title: d.name(lang))),
          link(context.tr('new_arrivals'), () => openCatalog(context, sort: 'newest', title: context.tr('new_arrivals'))),
        ]),
      ),
      SizedBox(
        width: 200,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.tr('footer_help').toUpperCase(), style: heading),
          link(context.tr('support'), () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SupportScreen()))),
          link(context.tr('my_orders'), () => openAccount(context)),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(context.tr('delivery_info_sub'), style: const TextStyle(color: BmColors.muted)),
          ),
        ]),
      ),
      SizedBox(
        width: 220,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.tr('footer_payment').toUpperCase(), style: heading),
          const SizedBox(height: 10),
          const Text('M-Pesa · Airtel Money\nVisa · Mastercard', style: TextStyle(color: BmColors.muted, height: 1.6)),
          Text(context.tr('pay_CASH_ON_DELIVERY'), style: const TextStyle(color: BmColors.muted, height: 1.6)),
        ]),
      ),
    ];

    return Container(
      margin: const EdgeInsets.only(top: 48),
      color: BmColors.surface,
      padding: EdgeInsets.fromLTRB(gutter, 40, gutter, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(spacing: 48, runSpacing: 32, children: columns),
          const SizedBox(height: 32),
          const Divider(color: BmColors.line),
          const SizedBox(height: 12),
          Text('© ${DateTime.now().year} Babymama · Nairobi, Kenya', style: const TextStyle(color: BmColors.muted, fontSize: 12)),
        ],
      ),
    );
  }
}
