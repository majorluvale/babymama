import 'package:babymama_core/babymama_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../widgets.dart';

const _bannerTypes = ['PROMO', 'NEW_ARRIVALS', 'PRODUCT', 'CATEGORY', 'BUNDLE', 'EXTERNAL'];

/// Home carousel (products, new arrivals, ads), bundle sales and multi-buy discounts.
class MarketingPage extends StatelessWidget {
  const MarketingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: PageHeader(
          title: context.tr('admin_marketing'),
          bottom: TabBar(tabs: [
            Tab(text: context.tr('carousel')),
            Tab(text: context.tr('bundles_title')),
            Tab(text: context.tr('multibuy_title')),
          ]),
        ),
        body: const TabBarView(children: [_BannersTab(), _BundlesTab(), _TiersTab()]),
      ),
    );
  }
}

// ---------------- Carousel banners ----------------

class _BannersTab extends StatefulWidget {
  const _BannersTab();

  @override
  State<_BannersTab> createState() => _BannersTabState();
}

class _BannersTabState extends State<_BannersTab> {
  int _version = 0;

  Future<void> _edit([BannerSlide? banner]) async {
    final saved = await showDialog<bool>(context: context, builder: (_) => _BannerDialog(banner: banner));
    if (saved == true) setState(() => _version++);
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    final lang = context.lang;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: Text(context.tr('new_slide')),
      ),
      body: AsyncBuilder<List<BannerSlide>>(
        key: ValueKey(_version),
        load: () async => (await api.get('/admin/banners') as List).whereType<Json>().map(BannerSlide.fromJson).toList(),
        builder: (context, banners, reload) {
          if (banners.isEmpty) return EmptyView(icon: Icons.view_carousel_outlined, message: context.tr('no_slides'));
          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: banners.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (context, i) {
              final b = banners[i];
              return ListTile(
                leading: BmImage(b.imageUrl, width: 120, height: 60, radius: 6),
                title: Text(b.title(lang)),
                subtitle: Text('${context.tr('banner_type_${b.type}')} · #${b.position}'
                    '${b.endsAt != null ? ' · ${context.tr('until')} ${formatDate(b.endsAt!)}' : ''}'),
                onTap: () => _edit(b),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Switch(
                    value: b.active,
                    onChanged: (v) async {
                      if (await runApi(context, () => api.patch('/admin/banners/${b.id}', {'active': v}))) reload();
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      if (!await confirmDialog(context, context.tr('delete_confirm'))) return;
                      if (context.mounted && await runApi(context, () => api.delete('/admin/banners/${b.id}'))) reload();
                    },
                  ),
                ]),
              );
            },
          );
        },
      ),
    );
  }
}

class _BannerDialog extends StatefulWidget {
  const _BannerDialog({this.banner});

  final BannerSlide? banner;

  @override
  State<_BannerDialog> createState() => _BannerDialogState();
}

class _BannerDialogState extends State<_BannerDialog> {
  late final b = widget.banner;
  late final _titleEn = TextEditingController(text: b?.titleEn);
  late final _titleFr = TextEditingController(text: b?.titleFr);
  late final _subEn = TextEditingController(text: b?.subtitleEn);
  late final _subFr = TextEditingController(text: b?.subtitleFr);
  late final _target = TextEditingController(text: b?.targetId);
  late final _url = TextEditingController(text: b?.url);
  late final _position = TextEditingController(text: '${b?.position ?? 0}');
  late String? _imageUrl = b?.imageUrl;
  late String _type = b?.type ?? 'PROMO';
  late bool _active = b?.active ?? true;
  late DateTime? _endsAt = b?.endsAt;

  String? _opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    if (_imageUrl == null || _titleEn.text.trim().isEmpty || _titleFr.text.trim().isEmpty) {
      showSnack(context, context.tr('banner_required_fields'), error: true);
      return;
    }
    final api = context.read<ApiClient>();
    final body = {
      'titleEn': _titleEn.text.trim(),
      'titleFr': _titleFr.text.trim(),
      'subtitleEn': _opt(_subEn),
      'subtitleFr': _opt(_subFr),
      'imageUrl': _imageUrl,
      'type': _type,
      'targetId': _opt(_target),
      'url': _opt(_url),
      'position': int.tryParse(_position.text) ?? 0,
      'active': _active,
      'endsAt': _endsAt?.toUtc().toIso8601String(),
    };
    final ok = await runApi(
      context,
      () => b == null ? api.post('/admin/banners', body) : api.patch('/admin/banners/${b!.id}', body),
    );
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final needsTarget = ['PRODUCT', 'CATEGORY', 'BUNDLE'].contains(_type);
    return AlertDialog(
      title: Text(b == null ? context.tr('new_slide') : context.tr('edit_slide')),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            InkWell(
              onTap: () async {
                final url = await pickAndUpload(context);
                if (url != null && mounted) setState(() => _imageUrl = url);
              },
              child: _imageUrl == null
                  ? Container(
                      height: 140,
                      width: double.infinity,
                      decoration: BoxDecoration(border: Border.all(color: BmColors.primary), borderRadius: BorderRadius.circular(8)),
                      child: Center(child: Text(context.tr('upload_image'))),
                    )
                  : BmImage(_imageUrl, height: 160, width: double.infinity, radius: 8),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: _titleEn, decoration: const InputDecoration(labelText: 'Title (EN)'))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _titleFr, decoration: const InputDecoration(labelText: 'Titre (FR)'))),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: _subEn, decoration: const InputDecoration(labelText: 'Subtitle (EN)'))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _subFr, decoration: const InputDecoration(labelText: 'Sous-titre (FR)'))),
            ]),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: InputDecoration(labelText: context.tr('slide_type')),
              items: [for (final t in _bannerTypes) DropdownMenuItem(value: t, child: Text(context.tr('banner_type_$t')))],
              onChanged: (v) => setState(() => _type = v ?? 'PROMO'),
            ),
            if (needsTarget) ...[
              const SizedBox(height: 8),
              TextField(controller: _target, decoration: InputDecoration(labelText: context.tr('target_id'), helperText: context.tr('target_id_hint'))),
            ],
            if (_type == 'EXTERNAL' || _type == 'PROMO') ...[
              const SizedBox(height: 8),
              TextField(controller: _url, decoration: InputDecoration(labelText: context.tr('link_optional'))),
            ],
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: _position, decoration: InputDecoration(labelText: context.tr('position')))),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      initialDate: _endsAt ?? DateTime.now().add(const Duration(days: 7)),
                    );
                    setState(() => _endsAt = d);
                  },
                  child: Text(_endsAt == null ? context.tr('no_end_date') : '${context.tr('until')} ${formatDate(_endsAt!)}'),
                ),
              ),
            ]),
            SwitchListTile(contentPadding: EdgeInsets.zero, value: _active, onChanged: (v) => setState(() => _active = v), title: Text(context.tr('active'))),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.tr('cancel'))),
        FilledButton(onPressed: _save, child: Text(context.tr('save'))),
      ],
    );
  }
}

// ---------------- Bundles (ventes groupées) ----------------

class _BundlesTab extends StatefulWidget {
  const _BundlesTab();

  @override
  State<_BundlesTab> createState() => _BundlesTabState();
}

class _BundlesTabState extends State<_BundlesTab> {
  int _version = 0;

  Future<void> _edit([Bundle? bundle]) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => BundleFormPage(bundle: bundle)));
    if (saved == true) setState(() => _version++);
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: Text(context.tr('new_bundle')),
      ),
      body: AsyncBuilder<List<Bundle>>(
        key: ValueKey(_version),
        load: () async => (await api.get('/admin/bundles') as List).whereType<Json>().map(Bundle.fromJson).toList(),
        builder: (context, bundles, reload) {
          if (bundles.isEmpty) return EmptyView(icon: Icons.all_inbox_outlined, message: context.tr('no_bundles'));
          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: bundles.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (context, i) {
              final b = bundles[i];
              return ListTile(
                leading: BmImage(b.imageUrl, width: 64, height: 64, radius: 6),
                title: Text(b.title),
                subtitle: Text('${formatKes(b.price)} (${formatKes(b.originalPrice)}) · '
                    '${context.tr('bundle_items', {'n': b.items.length})} · ${context.tr('available')}: ${b.available}'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  StatusChip(b.active ? 'ACTIVE' : 'ARCHIVED', prefix: 'product_status_'),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      if (!await confirmDialog(context, context.tr('delete_confirm'))) return;
                      if (context.mounted && await runApi(context, () => api.delete('/admin/bundles/${b.id}'))) reload();
                    },
                  ),
                ]),
                onTap: () => _edit(b),
              );
            },
          );
        },
      ),
    );
  }
}

class BundleFormPage extends StatefulWidget {
  const BundleFormPage({super.key, this.bundle});

  final Bundle? bundle;

  @override
  State<BundleFormPage> createState() => _BundleFormPageState();
}

class _BundleFormPageState extends State<BundleFormPage> {
  late final b = widget.bundle;
  late final _title = TextEditingController(text: b?.title);
  late final _titleFr = TextEditingController(text: b?.titleFr);
  late final _description = TextEditingController(text: b?.description);
  late final _price = TextEditingController(text: b == null ? '' : '${b!.price}');
  late String? _imageUrl = b?.imageUrl;
  late bool _active = b?.active ?? true;
  late final Map<String, (Product, int)> _items = {for (final i in b?.items ?? const <BundleItem>[]) i.productId: (i.product, i.quantity)};
  final _search = TextEditingController();
  List<Product> _results = [];

  int get _originalPrice => _items.values.fold(0, (s, e) => s + e.$1.price * e.$2);

  Future<void> _searchProducts() async {
    final res = await context.read<ApiClient>().get('/admin/products', query: {'q': _search.text.trim(), 'status': 'ACTIVE', 'pageSize': 20});
    if (mounted) setState(() => _results = Paged.fromJson(res as Json, Product.fromJson).items);
  }

  Future<void> _save() async {
    if (_title.text.trim().length < 2 || int.tryParse(_price.text.trim()) == null || _items.length < 2) {
      showSnack(context, context.tr('bundle_required_fields'), error: true);
      return;
    }
    final api = context.read<ApiClient>();
    final body = {
      'title': _title.text.trim(),
      'titleFr': _titleFr.text.trim().isEmpty ? null : _titleFr.text.trim(),
      'description': _description.text.trim(),
      'price': int.parse(_price.text.trim()),
      'imageUrl': _imageUrl,
      'active': _active,
      'items': [for (final e in _items.entries) {'productId': e.key, 'quantity': e.value.$2}],
    };
    final ok = await runApi(context, () => b == null ? api.post('/admin/bundles', body) : api.patch('/admin/bundles/${b!.id}', body));
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(b == null ? context.tr('new_bundle') : b!.title),
        actions: [FilledButton(onPressed: _save, child: Text(context.tr('save'))), const SizedBox(width: 16)],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                InkWell(
                  onTap: () async {
                    final url = await pickAndUpload(context);
                    if (url != null && mounted) setState(() => _imageUrl = url);
                  },
                  child: _imageUrl == null
                      ? Container(
                          width: 160,
                          height: 160,
                          decoration: BoxDecoration(border: Border.all(color: BmColors.primary), borderRadius: BorderRadius.circular(8)),
                          child: Center(child: Text(context.tr('upload_image'), textAlign: TextAlign.center)),
                        )
                      : BmImage(_imageUrl, width: 160, height: 160, radius: 8),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(children: [
                    TextField(controller: _title, decoration: const InputDecoration(labelText: 'Title (EN)')),
                    const SizedBox(height: 8),
                    TextField(controller: _titleFr, decoration: const InputDecoration(labelText: 'Titre (FR)')),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _price,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: context.tr('bundle_price'),
                        helperText: '${context.tr('items_value')}: ${formatKes(_originalPrice)}',
                      ),
                    ),
                  ]),
                ),
              ]),
              const SizedBox(height: 12),
              TextField(controller: _description, maxLines: 3, decoration: InputDecoration(labelText: context.tr('description'))),
              SwitchListTile(contentPadding: EdgeInsets.zero, value: _active, onChanged: (v) => setState(() => _active = v), title: Text(context.tr('active'))),
              const Divider(height: 32),
              Text(context.tr('bundle_items', {'n': _items.length}), style: const TextStyle(fontWeight: FontWeight.w700)),
              for (final e in _items.entries)
                ListTile(
                  leading: BmImage(e.value.$1.image, width: 44, height: 44, radius: 4),
                  title: Text(e.value.$1.title),
                  subtitle: Text('${e.value.$1.sku} · ${formatKes(e.value.$1.price)} · ${context.tr('stock')}: ${e.value.$1.stock}'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      icon: const Icon(Icons.remove),
                      onPressed: () => setState(() {
                        final q = e.value.$2 - 1;
                        if (q <= 0) {
                          _items.remove(e.key);
                        } else {
                          _items[e.key] = (e.value.$1, q);
                        }
                      }),
                    ),
                    Text('${e.value.$2}'),
                    IconButton(icon: const Icon(Icons.add), onPressed: () => setState(() => _items[e.key] = (e.value.$1, e.value.$2 + 1))),
                  ]),
                ),
              const SizedBox(height: 16),
              TextField(
                controller: _search,
                decoration: InputDecoration(
                  hintText: context.tr('add_product_to_bundle'),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _searchProducts),
                ),
                onSubmitted: (_) => _searchProducts(),
              ),
              for (final p in _results.where((p) => !_items.containsKey(p.id)))
                ListTile(
                  dense: true,
                  leading: BmImage(p.image, width: 36, height: 36, radius: 4),
                  title: Text(p.title),
                  subtitle: Text('${p.sku} · ${formatKes(p.price)} · ${context.tr('stock')}: ${p.stock}'),
                  trailing: const Icon(Icons.add_circle_outline),
                  onTap: () => setState(() => _items[p.id] = (p, 1)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- Multi-buy discount tiers ----------------

class _TiersTab extends StatefulWidget {
  const _TiersTab();

  @override
  State<_TiersTab> createState() => _TiersTabState();
}

class _TiersTabState extends State<_TiersTab> {
  List<(TextEditingController, TextEditingController)> _rows = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    context.read<ApiClient>().get('/admin/discount-tiers').then((list) {
      if (!mounted) return;
      setState(() {
        _rows = [
          for (final t in (list as List).whereType<Json>().map(DiscountTier.fromJson))
            (TextEditingController(text: '${t.minItems}'), TextEditingController(text: '${t.percent}')),
        ];
        _loaded = true;
      });
    }).catchError((_) {});
  }

  Future<void> _save() async {
    final tiers = [
      for (final (min, pct) in _rows)
        if (int.tryParse(min.text) != null && int.tryParse(pct.text) != null)
          {'minItems': int.parse(min.text), 'percent': int.parse(pct.text), 'active': true},
    ];
    final api = context.read<ApiClient>();
    await runApi(context, () => api.put('/admin/discount-tiers', tiers), success: context.tr('saved'));
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(context.tr('multibuy_explain'), style: const TextStyle(color: BmColors.muted)),
        const SizedBox(height: 16),
        for (var i = 0; i < _rows.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              SizedBox(
                width: 180,
                child: TextField(controller: _rows[i].$1, decoration: InputDecoration(labelText: context.tr('min_items'))),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 180,
                child: TextField(controller: _rows[i].$2, decoration: InputDecoration(labelText: context.tr('percent_off'))),
              ),
              IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => setState(() => _rows.removeAt(i))),
            ]),
          ),
        Row(children: [
          OutlinedButton.icon(
            onPressed: () => setState(() => _rows.add((TextEditingController(), TextEditingController()))),
            icon: const Icon(Icons.add),
            label: Text(context.tr('add_tier')),
          ),
          const SizedBox(width: 12),
          FilledButton(onPressed: _save, child: Text(context.tr('save'))),
        ]),
      ],
    );
  }
}
