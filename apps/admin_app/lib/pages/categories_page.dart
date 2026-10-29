import 'package:babymama_core/babymama_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../widgets.dart';

const _sizeTypes = ['CLOTHING', 'KIDS_AGE', 'SHOES', 'ONE_SIZE'];

/// Departments (Women, Men, Kids...) and their sub-categories: names, icon, size scale, order.
class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key});

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  int _version = 0;

  Future<List<Category>> _load() async {
    final list = await context.read<ApiClient>().get('/categories') as List;
    return list.whereType<Json>().map(Category.fromJson).toList();
  }

  Future<void> _edit(List<Category> all, {Category? category, String? parentId}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _CategoryDialog(all: all, category: category, parentId: parentId ?? category?.parentId),
    );
    if (saved == true) setState(() => _version++);
  }

  Future<void> _delete(Category c) async {
    if (!await confirmDialog(context, context.tr('category_delete_confirm', {'name': c.name(context.lang)}))) return;
    if (!mounted) return;
    final api = context.read<ApiClient>();
    if (await runApi(context, () => api.delete('/admin/categories/${c.id}'))) setState(() => _version++);
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.lang;
    return Scaffold(
      appBar: PageHeader(title: context.tr('admin_categories')),
      body: AsyncBuilder<List<Category>>(
        key: ValueKey(_version),
        load: _load,
        builder: (context, all, _) {
          final departments = all.where((c) => c.parentId == null).toList();
          String scale(Category c) =>
              c.ownSizeType != null ? context.tr('size_type_${c.ownSizeType}') : context.tr('size_type_inherit', {'type': context.tr('size_type_${c.sizeType}')});
          return Stack(children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                for (final d in departments)
                  Card(
                    elevation: 0,
                    color: BmColors.surface,
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(children: [
                        ListTile(
                          leading: CategoryIcon(d.icon, size: 28),
                          title: Text(d.name(lang), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                          subtitle: Text('${d.slug} · ${scale(d)}'),
                          trailing: Wrap(spacing: 4, children: [
                            TextButton.icon(
                              onPressed: () => _edit(all, parentId: d.id),
                              icon: const Icon(Icons.add, size: 18),
                              label: Text(context.tr('add_subcategory')),
                            ),
                            IconButton(tooltip: context.tr('edit'), icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(all, category: d)),
                            IconButton(tooltip: context.tr('delete'), icon: const Icon(Icons.delete_outline), onPressed: () => _delete(d)),
                          ]),
                        ),
                        const Divider(height: 1),
                        for (final c in all.where((c) => c.parentId == d.id))
                          ListTile(
                            contentPadding: const EdgeInsets.only(left: 40, right: 16),
                            leading: CategoryIcon(c.icon),
                            title: Text(c.name(lang)),
                            subtitle: Text('${lang == 'fr' ? c.nameEn : c.nameFr} · ${scale(c)}'),
                            trailing: Wrap(spacing: 4, children: [
                              IconButton(tooltip: context.tr('edit'), icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(all, category: c)),
                              IconButton(tooltip: context.tr('delete'), icon: const Icon(Icons.delete_outline), onPressed: () => _delete(c)),
                            ]),
                            onTap: () => _edit(all, category: c),
                          ),
                      ]),
                    ),
                  ),
              ],
            ),
            Positioned(
              right: 24,
              bottom: 24,
              child: FloatingActionButton.extended(
                onPressed: () => _edit(all),
                icon: const Icon(Icons.add),
                label: Text(context.tr('new_department')),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({required this.all, this.category, this.parentId});

  final List<Category> all;
  final Category? category;
  final String? parentId;

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late final _nameFr = TextEditingController(text: widget.category?.nameFr);
  late final _nameEn = TextEditingController(text: widget.category?.nameEn);
  late final _position = TextEditingController(text: '${widget.category?.position ?? widget.all.length}');
  late String? _parentId = widget.parentId;
  late String? _sizeType = widget.category?.ownSizeType;
  late String? _icon = widget.category?.icon;
  bool _busy = false;

  @override
  void dispose() {
    _nameFr.dispose();
    _nameEn.dispose();
    _position.dispose();
    super.dispose();
  }

  /// "Jeans & trousers" under "women" -> "women-jeans-trousers".
  String _slug() {
    final parent = widget.all.where((c) => c.id == _parentId).firstOrNull;
    final base = _nameEn.text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return parent == null ? base : '${parent.slug}-$base';
  }

  Future<void> _save() async {
    if (_nameFr.text.trim().isEmpty || _nameEn.text.trim().isEmpty) {
      showSnack(context, context.tr('required'), error: true);
      return;
    }
    final api = context.read<ApiClient>();
    final body = {
      if (widget.category == null) 'slug': _slug(),
      'nameFr': _nameFr.text.trim(),
      'nameEn': _nameEn.text.trim(),
      'parentId': _parentId,
      'sizeType': _sizeType,
      'icon': _icon,
      'position': int.tryParse(_position.text.trim()) ?? 0,
    };
    setState(() => _busy = true);
    final ok = await runApi(
      context,
      () => widget.category == null ? api.post('/admin/categories', body) : api.patch('/admin/categories/${widget.category!.id}', body),
      success: context.tr('saved'),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.lang;
    final departments = widget.all.where((c) => c.parentId == null && c.id != widget.category?.id).toList();
    return AlertDialog(
      title: Text(widget.category == null ? context.tr(_parentId == null ? 'new_department' : 'add_subcategory') : widget.category!.name(lang)),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: TextField(controller: _nameFr, decoration: InputDecoration(labelText: context.tr('name_fr')))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: _nameEn, decoration: InputDecoration(labelText: context.tr('name_en')))),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String?>(
                  initialValue: _parentId,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: context.tr('department')),
                  items: [
                    DropdownMenuItem(value: null, child: Text(context.tr('none_is_department'))),
                    for (final d in departments) DropdownMenuItem(value: d.id, child: Text(d.name(lang))),
                  ],
                  onChanged: (v) => setState(() => _parentId = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(controller: _position, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: context.tr('position'))),
              ),
            ]),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _sizeType,
              isExpanded: true,
              decoration: InputDecoration(labelText: context.tr('size_scale')),
              items: [
                DropdownMenuItem(value: null, child: Text(context.tr('size_type_same_as_department'))),
                for (final t in _sizeTypes) DropdownMenuItem(value: t, child: Text(context.tr('size_type_$t'))),
              ],
              onChanged: (v) => setState(() => _sizeType = v),
            ),
            const SizedBox(height: 16),
            Text(context.tr('icon'), style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final key in categoryIconPaths.keys)
                  Tooltip(
                    message: key,
                    child: InkWell(
                      onTap: () => setState(() => _icon = key),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _icon == key ? BmColors.ink : BmColors.surface,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: CategoryIcon(key, size: 24, color: _icon == key ? Colors.white : BmColors.ink),
                      ),
                    ),
                  ),
              ],
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.tr('cancel'))),
        FilledButton(onPressed: _busy ? null : _save, child: Text(context.tr('save'))),
      ],
    );
  }
}
