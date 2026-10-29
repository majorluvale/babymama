import 'package:babymama_core/babymama_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../widgets.dart';

const productStatuses = ['ACTIVE', 'PENDING_REVIEW', 'SOLD_OUT', 'DRAFT', 'ARCHIVED', 'REJECTED'];

/// Products added from this back-office, from WooCommerce (webhook / import) or submitted by customers.
class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  final _search = TextEditingController();
  String? _status;
  int _page = 1;
  int _version = 0;

  void _reload() => setState(() => _version++);

  Future<void> _openForm([Product? product]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ProductFormPage(product: product)),
    );
    if (saved == true) _reload();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    return Scaffold(
      appBar: PageHeader(
        title: context.tr('admin_products'),
        actions: [FilledButton.icon(onPressed: () => _openForm(), icon: const Icon(Icons.add), label: Text(context.tr('new_product')))],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  decoration: InputDecoration(hintText: context.tr('search_products_admin'), prefixIcon: const Icon(Icons.search)),
                  onSubmitted: (_) => setState(() {
                    _page = 1;
                    _version++;
                  }),
                ),
              ),
              const SizedBox(width: 12),
              DropdownButton<String?>(
                value: _status,
                hint: Text(context.tr('all_statuses')),
                items: [
                  DropdownMenuItem<String?>(value: null, child: Text(context.tr('all_statuses'))),
                  for (final s in productStatuses) DropdownMenuItem<String?>(value: s, child: Text(context.tr('product_status_$s'))),
                ],
                onChanged: (v) => setState(() {
                  _status = v;
                  _page = 1;
                }),
              ),
            ]),
            const SizedBox(height: 8),
            Expanded(
              child: AsyncBuilder<Paged<Product>>(
                key: ValueKey('$_status|$_page|$_version'),
                load: () async => Paged.fromJson(
                  await api.get('/admin/products', query: {
                    'q': _search.text.trim(),
                    'status': _status,
                    'page': _page,
                    'pageSize': 30,
                  }) as Json,
                  Product.fromJson,
                ),
                builder: (context, page, reload) {
                  if (page.items.isEmpty) return EmptyView(message: context.tr('no_products'));
                  return Column(children: [
                    Expanded(
                      child: ListView.separated(
                        itemCount: page.items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) => _ProductRow(
                          product: page.items[i],
                          onEdit: () => _openForm(page.items[i]),
                          onChanged: reload,
                        ),
                      ),
                    ),
                    Pager(page: page.page, pages: page.pages, total: page.total, onPage: (p) => setState(() => _page = p)),
                  ]);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product, required this.onEdit, required this.onChanged});

  final Product product;
  final VoidCallback onEdit;
  final Future<void> Function() onChanged;

  Future<void> _setStatus(BuildContext context, String status, {String? reason}) async {
    final api = context.read<ApiClient>();
    final ok = await runApi(context, () => api.patch('/admin/products/${product.id}', {
          'status': status,
          if (reason != null) 'rejectReason': reason,
        }));
    if (ok) onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final p = product;
    return ListTile(
      leading: BmImage(p.image, width: 52, height: 52, radius: 6),
      title: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text([
        p.sku,
        formatKes(p.price),
        if (p.category != null) p.category!.path(context.lang),
        if (p.size != null) p.size!,
        if (p.color != null) context.colorName(p.color!),
        context.tr('source_${p.source}'),
        if (p.sellerName != null) '${context.tr('seller')}: ${p.sellerName}',
      ].join(' · ')),
      onTap: onEdit,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('${context.tr('stock')}: ${p.stock}',
            style: TextStyle(fontWeight: FontWeight.w700, color: p.isLowStock ? BmColors.danger : null)),
        const SizedBox(width: 12),
        StatusChip(p.status, prefix: 'product_status_'),
        if (p.status == 'PENDING_REVIEW') ...[
          IconButton(
            tooltip: context.tr('approve'),
            icon: const Icon(Icons.check_circle_outline, color: BmColors.success),
            onPressed: () => _setStatus(context, 'ACTIVE'),
          ),
          IconButton(
            tooltip: context.tr('reject'),
            icon: const Icon(Icons.cancel_outlined, color: BmColors.danger),
            onPressed: () async {
              final reason = await promptText(context, context.tr('reject_reason'));
              if (reason != null && context.mounted) _setStatus(context, 'REJECTED', reason: reason);
            },
          ),
        ],
        IconButton(
          tooltip: context.tr('adjust_stock'),
          icon: const Icon(Icons.inventory_2_outlined),
          onPressed: () async {
            if (await showStockDialog(context, p)) onChanged();
          },
        ),
      ]),
    );
  }
}

/// Restock / correction / customer return. Returns true when saved.
Future<bool> showStockDialog(BuildContext context, Product product) async {
  final qty = TextEditingController();
  final reason = TextEditingController();
  var type = 'RESTOCK';
  final api = context.read<ApiClient>();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text('${ctx.tr('adjust_stock')} · ${product.title}'),
        content: SizedBox(
          width: 400,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${ctx.tr('current_stock')}: ${product.stock}'),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'RESTOCK', label: Text(ctx.tr('movement_RESTOCK'))),
                ButtonSegment(value: 'ADJUSTMENT', label: Text(ctx.tr('movement_ADJUSTMENT'))),
                ButtonSegment(value: 'RETURN', label: Text(ctx.tr('movement_RETURN'))),
              ],
              selected: {type},
              onSelectionChanged: (s) => setState(() => type = s.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: qty,
              keyboardType: const TextInputType.numberWithOptions(signed: true),
              decoration: InputDecoration(
                labelText: ctx.tr('quantity'),
                helperText: type == 'ADJUSTMENT' ? ctx.tr('adjustment_hint') : null,
              ),
            ),
            const SizedBox(height: 12),
            TextField(controller: reason, decoration: InputDecoration(labelText: ctx.tr('reason'))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('save'))),
        ],
      ),
    ),
  );
  final quantity = int.tryParse(qty.text.trim());
  if (ok != true || quantity == null || quantity == 0 || !context.mounted) return false;
  return runApi(
    context,
    () => api.post('/admin/products/${product.id}/stock', {
      'type': type,
      'quantity': quantity,
      if (reason.text.trim().isNotEmpty) 'reason': reason.text.trim(),
    }),
    success: context.tr('saved'),
  );
}

class ProductFormPage extends StatefulWidget {
  const ProductFormPage({super.key, this.product});

  final Product? product;

  @override
  State<ProductFormPage> createState() => _ProductFormPageState();
}

class _ProductFormPageState extends State<ProductFormPage> {
  final _form = GlobalKey<FormState>();
  late final Product? _p = widget.product;
  late final _title = TextEditingController(text: _p?.title);
  late final _description = TextEditingController(text: _p?.description);
  late final _brand = TextEditingController(text: _p?.brand);
  late String? _size = _p?.size;
  late String? _color = _p?.color;
  late final _sku = TextEditingController(text: _p?.sku);
  late final _price = TextEditingController(text: _p?.price.toString());
  late final _compareAt = TextEditingController(text: _p?.compareAtPrice?.toString());
  late final _stock = TextEditingController(text: '1');
  late final _lowStock = TextEditingController(text: (_p?.lowStockThreshold ?? 1).toString());
  late final List<String> _images = [...?_p?.images];
  late String _condition = _p?.condition ?? 'GOOD';
  late String _status = _p?.status ?? 'ACTIVE';
  late bool _featured = _p?.isFeatured ?? false;
  late String? _categoryId = _p?.category?.id;
  List<Category> _categories = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    context.read<ApiClient>().get('/categories').then((list) {
      final all = (list as List).whereType<Json>().map(Category.fromJson).toList();
      // Each department followed by its sub-categories: Women, Dresses, ..., Men, Shirts, ...
      final ordered = [
        for (final d in all.where((c) => c.parentId == null)) ...[d, ...all.where((c) => c.parentId == d.id)],
      ];
      if (mounted) setState(() => _categories = ordered);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    for (final c in [_title, _description, _brand, _sku, _price, _compareAt, _stock, _lowStock]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Category? get _category => _categories.where((c) => c.id == _categoryId).firstOrNull;

  /// Sizes of the chosen category: S/M/L, age, shoe number, or none for accessories.
  List<String> get _sizes => _category?.sizes ?? const [];

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final api = context.read<ApiClient>();
    final body = <String, dynamic>{
      'title': _title.text.trim(),
      'description': _description.text.trim(),
      'brand': _opt(_brand),
      'size': _sizes.contains(_size) ? _size : null,
      'color': _color,
      'condition': _condition,
      'price': int.parse(_price.text.trim()),
      'compareAtPrice': int.tryParse(_compareAt.text.trim()),
      'categoryId': _categoryId,
      'images': _images,
      'status': _status,
      'isFeatured': _featured,
      'lowStockThreshold': int.tryParse(_lowStock.text.trim()) ?? 1,
      if (_opt(_sku) != null) 'sku': _opt(_sku),
      if (_p == null) 'stock': int.tryParse(_stock.text.trim()) ?? 0,
    };
    setState(() => _busy = true);
    final ok = await runApi(
      context,
      () => _p == null ? api.post('/admin/products', body) : api.patch('/admin/products/${_p.id}', body),
      success: context.tr('saved'),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, true);
  }

  Future<void> _archive() async {
    if (!await confirmDialog(context, context.tr('archive_confirm'))) return;
    if (!mounted) return;
    final api = context.read<ApiClient>();
    final ok = await runApi(context, () => api.delete('/admin/products/${_p!.id}'));
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.lang;
    String? required(String? v) => (v ?? '').trim().isEmpty ? context.tr('required') : null;
    return Scaffold(
      appBar: AppBar(
        title: Text(_p == null ? context.tr('new_product') : _p.title),
        actions: [
          if (_p != null) TextButton(onPressed: _archive, child: Text(context.tr('archive'), style: const TextStyle(color: BmColors.danger))),
          const SizedBox(width: 8),
          FilledButton(onPressed: _busy ? null : _save, child: Text(context.tr('save'))),
          const SizedBox(width: 16),
        ],
      ),
      body: Form(
        key: _form,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(context.tr('photos'), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (var i = 0; i < _images.length; i++)
                    Stack(children: [
                      BmImage(_images[i], width: 110, height: 140, radius: 8),
                      Positioned(
                        right: 0,
                        child: IconButton(
                          icon: const Icon(Icons.cancel, color: Colors.white),
                          onPressed: () => setState(() => _images.removeAt(i)),
                        ),
                      ),
                    ]),
                  InkWell(
                    onTap: () async {
                      final url = await pickAndUpload(context);
                      if (url != null && mounted) setState(() => _images.add(url));
                    },
                    child: Container(
                      width: 110,
                      height: 140,
                      decoration: BoxDecoration(border: Border.all(color: BmColors.primary), borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.add_a_photo_outlined, color: BmColors.primary),
                    ),
                  ),
                ]),
                const SizedBox(height: 20),
                TextFormField(controller: _title, decoration: InputDecoration(labelText: context.tr('title')), validator: required),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _description,
                  minLines: 3,
                  maxLines: 8,
                  decoration: InputDecoration(labelText: context.tr('description'), alignLabelWithHint: true),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _price,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: context.tr('price_kes')),
                      validator: (v) => int.tryParse((v ?? '').trim()) == null ? context.tr('invalid_price') : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _compareAt,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: context.tr('compare_at_price')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: TextFormField(controller: _sku, decoration: const InputDecoration(labelText: 'SKU'))),
                ]),
                const SizedBox(height: 12),
                // The category decides which sizes exist, so it comes first.
                Row(children: [
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(_categories.length),
                      initialValue: _categories.any((c) => c.id == _categoryId) ? _categoryId : null,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: context.tr('category')),
                      validator: (v) => v == null ? context.tr('required') : null,
                      items: [
                        for (final c in _categories)
                          DropdownMenuItem(
                            value: c.id,
                            child: Text(
                              c.parentId == null ? c.name(lang).toUpperCase() : '      ${c.name(lang)}',
                              style: TextStyle(fontWeight: c.parentId == null ? FontWeight.w700 : FontWeight.normal),
                            ),
                          ),
                      ],
                      selectedItemBuilder: (_) => [for (final c in _categories) Text(c.path(lang))],
                      onChanged: (v) => setState(() {
                        _categoryId = v;
                        if (!_sizes.contains(_size)) _size = null;
                      }),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _sizes.isEmpty
                        ? InputDecorator(
                            decoration: InputDecoration(labelText: context.tr('size')),
                            child: Text(
                              _category == null ? '-' : context.tr('one_size'),
                              style: const TextStyle(color: BmColors.muted),
                            ),
                          )
                        : DropdownButtonFormField<String>(
                            key: ValueKey('size-$_categoryId'),
                            initialValue: _sizes.contains(_size) ? _size : null,
                            isExpanded: true,
                            decoration: InputDecoration(labelText: context.tr('size')),
                            validator: (v) => v == null ? context.tr('required') : null,
                            items: [for (final s in _sizes) DropdownMenuItem(value: s, child: Text(s))],
                            onChanged: (v) => setState(() => _size = v),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _color,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: context.tr('color')),
                      items: [
                        // A colour imported from WooCommerce that is not in the list stays selectable.
                        if (_color != null && !productColors.containsKey(_color)) DropdownMenuItem(value: _color, child: Text(_color!)),
                        for (final key in productColors.keys)
                          DropdownMenuItem(
                            value: key,
                            child: Row(children: [ColorSwatchDot(key, size: 14), const SizedBox(width: 8), Text(context.colorName(key))]),
                          ),
                      ],
                      onChanged: (v) => setState(() => _color = v),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: TextFormField(controller: _brand, decoration: InputDecoration(labelText: context.tr('brand')))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _condition,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: context.tr('condition')),
                      items: [for (final c in productConditions) DropdownMenuItem(value: c, child: Text(context.tr('condition_$c')))],
                      onChanged: (v) => setState(() => _condition = v ?? 'GOOD'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _status,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: context.tr('status')),
                      items: [for (final s in productStatuses) DropdownMenuItem(value: s, child: Text(context.tr('product_status_$s')))],
                      onChanged: (v) => setState(() => _status = v ?? 'ACTIVE'),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  if (_p == null) ...[
                    Expanded(
                      child: TextFormField(
                        controller: _stock,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: context.tr('initial_stock')),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ] else
                    Expanded(child: Text('${context.tr('current_stock')}: ${_p.stock}  (${context.tr('stock_edit_hint')})')),
                  Expanded(
                    child: TextFormField(
                      controller: _lowStock,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: context.tr('low_stock_threshold')),
                    ),
                  ),
                ]),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _featured,
                  onChanged: (v) => setState(() => _featured = v),
                  title: Text(context.tr('featured_on_home')),
                ),
                if (_p?.wooId != null)
                  Text('WooCommerce #${_p!.wooId}', style: const TextStyle(color: BmColors.muted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
