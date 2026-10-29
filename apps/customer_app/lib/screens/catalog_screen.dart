import 'dart:async';

import 'package:babymama_core/babymama_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/categories.dart';
import '../widgets/shop_widgets.dart';
import '../widgets/site_layout.dart';

const _sorts = ['newest', 'price_asc', 'price_desc', 'popular'];

/// Filters of the catalog, shared by the side column (website) and the bottom sheet (phones).
class _Filters extends ChangeNotifier {
  _Filters({this.categoryId, this.query, this.sort = 'newest'});

  String? categoryId;
  String? query;
  String sort;
  String? condition;
  final Set<String> sizes = {};
  final Set<String> colors = {};
  int? minPrice;
  int? maxPrice;

  int get count => [condition, minPrice, maxPrice].where((v) => v != null).length + sizes.length + colors.length;

  void update(void Function(_Filters f) change) {
    change(this);
    notifyListeners();
  }

  void setCategory(String? id) => update((f) {
        f.categoryId = id;
        f.sizes.clear(); // sizes depend on the category
      });

  void clear() => update((f) {
        f.condition = null;
        f.minPrice = null;
        f.maxPrice = null;
        f.sizes.clear();
        f.colors.clear();
      });

  Map<String, dynamic> toQuery() => {
        'q': query,
        'category': categoryId,
        'condition': condition,
        'size': sizes.isEmpty ? null : sizes.join(','),
        'color': colors.isEmpty ? null : colors.join(','),
        'minPrice': minPrice,
        'maxPrice': maxPrice,
        'sort': sort,
      };
}

/// Product listing: category, search results or new arrivals, with filters and infinite scroll.
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key, this.categoryId, this.initialQuery, this.initialSort = 'newest', this.title});

  final String? categoryId;
  final String? initialQuery;
  final String initialSort;
  final String? title;

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  late final _filters = _Filters(categoryId: widget.categoryId, query: widget.initialQuery, sort: widget.initialSort);
  final _scroll = ScrollController();
  Timer? _debounce;

  final List<Product> _items = [];
  int _page = 0;
  int _total = 0;
  bool _hasMore = true;
  bool _loading = false;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 800) _loadMore();
    });
    _filters.addListener(() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 200), _reset);
    });
    context.read<CategoriesController>().load();
    _reset();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _filters.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _reset() async {
    _generation++;
    setState(() {
      _items.clear();
      _page = 0;
      _hasMore = true;
      _loading = false;
      _error = null;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    final generation = _generation;
    setState(() => _loading = true);
    try {
      final res = await context.read<ApiClient>().get('/products', query: {
        'page': _page + 1,
        'pageSize': 24,
        ..._filters.toQuery(),
      }) as Json;
      final page = Paged.fromJson(res, Product.fromJson);
      if (!mounted || generation != _generation) return;
      setState(() {
        _items.addAll(page.items);
        _page = page.page;
        _total = page.total;
        _hasMore = page.hasMore;
      });
    } on ApiException catch (e) {
      if (mounted && generation == _generation) setState(() => _error = e.message);
    } finally {
      if (mounted && generation == _generation) setState(() => _loading = false);
    }
  }

  String _title(CategoriesController categories) {
    final c = categories.byId(_filters.categoryId);
    if (c != null) return c.path(context.lang);
    if (_filters.query != null && _filters.query!.isNotEmpty) return '« ${_filters.query} »';
    return widget.title ?? context.tr('all_items');
  }

  Future<void> _openFilterSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        builder: (ctx, scroll) => Column(
          children: [
            Expanded(child: _FilterPanel(filters: _filters, scrollController: scroll)),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('show_results'))),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = context.watch<CategoriesController>();
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= kWideBreakpoint;
    final gutter = siteGutter(width);

    final toolbar = ListenableBuilder(
      listenable: _filters,
      builder: (context, _) => Row(
        children: [
          Text(context.tr('n_items', {'n': _total}), style: const TextStyle(color: BmColors.muted)),
          const Spacer(),
          if (!wide)
            TextButton.icon(
              onPressed: _openFilterSheet,
              style: TextButton.styleFrom(foregroundColor: BmColors.ink),
              icon: Badge(isLabelVisible: _filters.count > 0, label: Text('${_filters.count}'), child: const Icon(Icons.tune, size: 20)),
              label: Text(context.tr('filters')),
            ),
          PopupMenuButton<String>(
            tooltip: context.tr('sort_by'),
            initialValue: _filters.sort,
            onSelected: (s) => _filters.update((f) => f.sort = s),
            itemBuilder: (_) => [for (final s in _sorts) PopupMenuItem(value: s, child: Text(context.tr('sort_$s')))],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('${context.tr('sort_by')} : ', style: const TextStyle(color: BmColors.muted)),
                Text(context.tr('sort_${_filters.sort}'), style: const TextStyle(fontWeight: FontWeight.w600)),
                const Icon(Icons.expand_more, size: 20),
              ]),
            ),
          ),
        ],
      ),
    );

    final results = _buildResults(wide ? 0 : gutter);
    final body = wide
        ? Padding(
            padding: EdgeInsets.symmetric(horizontal: gutter),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 250, child: _FilterPanel(filters: _filters)),
                const SizedBox(width: 32),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 24),
                      Text(_title(categories), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      toolbar,
                      const Divider(color: BmColors.line),
                      Expanded(child: results),
                    ],
                  ),
                ),
              ],
            ),
          )
        : Column(
            children: [
              Padding(padding: EdgeInsets.fromLTRB(gutter, 4, gutter, 0), child: toolbar),
              Expanded(child: results),
            ],
          );

    return SiteScaffold(fullWidth: true, title: wide ? null : _title(categories), body: body);
  }

  Widget _buildResults(double gutter) {
    if (_error != null && _items.isEmpty) return ErrorView(message: _error!, onRetry: _reset);
    if (_items.isEmpty && _loading) return const Center(child: CircularProgressIndicator());
    if (_items.isEmpty) return EmptyView(message: context.tr('no_results'), icon: Icons.search_off);
    return RefreshIndicator(
      onRefresh: _reset,
      child: CustomScrollView(
        controller: _scroll,
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          ProductSliverGrid(products: _items, gutter: gutter, maxColumns: 4),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(child: _loading ? const CircularProgressIndicator() : const SizedBox.shrink()),
            ),
          ),
        ],
      ),
    );
  }
}

/// Category tree, sizes of the chosen category, colours, condition and price.
class _FilterPanel extends StatefulWidget {
  const _FilterPanel({required this.filters, this.scrollController});

  final _Filters filters;
  final ScrollController? scrollController;

  @override
  State<_FilterPanel> createState() => _FilterPanelState();
}

class _FilterPanelState extends State<_FilterPanel> {
  late final _min = TextEditingController(text: widget.filters.minPrice?.toString());
  late final _max = TextEditingController(text: widget.filters.maxPrice?.toString());

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  void _applyPrice() => widget.filters.update((f) {
        f.minPrice = int.tryParse(_min.text.trim());
        f.maxPrice = int.tryParse(_max.text.trim());
      });

  @override
  Widget build(BuildContext context) {
    final lang = context.lang;
    final categories = context.watch<CategoriesController>();
    return ListenableBuilder(
      listenable: widget.filters,
      builder: (context, _) {
        final f = widget.filters;
        final selected = categories.byId(f.categoryId);
        final department = categories.departmentOf(f.categoryId);
        final sizes = selected?.sizes ?? const <String>[];

        Widget heading(String text) => Padding(
              padding: const EdgeInsets.only(top: 24, bottom: 10),
              child: Text(text.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 1)),
            );
        Widget categoryLink(Category c, {bool bold = false, double indent = 0}) {
          final active = f.categoryId == c.id;
          final color = active ? BmColors.primary : BmColors.ink;
          return InkWell(
            onTap: () => f.setCategory(c.id),
            child: Padding(
              padding: EdgeInsets.only(left: indent, top: 6, bottom: 6),
              child: Row(children: [
                CategoryIcon(c.icon, size: 18, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    c.name(lang),
                    style: TextStyle(
                      fontWeight: active || bold ? FontWeight.w700 : FontWeight.w400,
                      color: color,
                      decoration: active ? TextDecoration.underline : null,
                    ),
                  ),
                ),
              ]),
            ),
          );
        }

        return ListView(
          controller: widget.scrollController,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            heading(context.tr('category')),
            if (department == null)
              for (final d in categories.departments) categoryLink(d, bold: true)
            else ...[
              InkWell(
                onTap: () => f.setCategory(null),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(children: [
                    const Icon(Icons.chevron_left, size: 18, color: BmColors.muted),
                    Text(context.tr('all_items'), style: const TextStyle(color: BmColors.muted)),
                  ]),
                ),
              ),
              categoryLink(department, bold: true),
              for (final c in categories.childrenOf(department.id)) categoryLink(c, indent: 12),
            ],
            heading(context.tr('size')),
            if (selected == null)
              Text(context.tr('size_pick_category'), style: const TextStyle(color: BmColors.muted, fontSize: 13))
            else if (sizes.isEmpty)
              Text(context.tr('one_size'), style: const TextStyle(color: BmColors.muted, fontSize: 13))
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in sizes)
                    _SizeBox(
                      label: s,
                      selected: f.sizes.contains(s),
                      onTap: () => f.update((f) => f.sizes.contains(s) ? f.sizes.remove(s) : f.sizes.add(s)),
                    ),
                ],
              ),
            heading(context.tr('color')),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final key in productColors.keys)
                  Tooltip(
                    message: context.colorName(key),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => f.update((f) => f.colors.contains(key) ? f.colors.remove(key) : f.colors.add(key)),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: ColorSwatchDot(key, size: 24, selected: f.colors.contains(key)),
                      ),
                    ),
                  ),
              ],
            ),
            heading(context.tr('condition')),
            for (final c in productConditions)
              InkWell(
                onTap: () => f.update((f) => f.condition = f.condition == c ? null : c),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Icon(f.condition == c ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                        size: 18, color: f.condition == c ? BmColors.primary : BmColors.muted),
                    const SizedBox(width: 8),
                    Text(context.tr('condition_$c')),
                  ]),
                ),
              ),
            heading(context.tr('price')),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _min,
                  keyboardType: TextInputType.number,
                  onSubmitted: (_) => _applyPrice(),
                  decoration: InputDecoration(isDense: true, hintText: context.tr('min_price')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _max,
                  keyboardType: TextInputType.number,
                  onSubmitted: (_) => _applyPrice(),
                  decoration: InputDecoration(isDense: true, hintText: context.tr('max_price')),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _applyPrice, child: Text(context.tr('apply'))),
            if (f.count > 0) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () {
                  _min.clear();
                  _max.clear();
                  f.clear();
                },
                icon: const Icon(Icons.close, size: 18),
                label: Text(context.tr('clear_all')),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _SizeBox extends StatelessWidget {
  const _SizeBox({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        constraints: const BoxConstraints(minWidth: 44),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? BmColors.ink : Colors.white,
          border: Border.all(color: selected ? BmColors.ink : BmColors.line),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: selected ? Colors.white : BmColors.ink, fontWeight: FontWeight.w500)),
      ),
    );
  }
}
