import 'dart:async';

import 'package:babymama_core/babymama_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/categories.dart';
import 'shop_widgets.dart';
import 'site_layout.dart';

/// Website search: a field in the header with a results panel that drops down under it.
class SiteSearchField extends StatefulWidget {
  const SiteSearchField({super.key, this.maxWidth = 520});

  final double maxWidth;

  @override
  State<SiteSearchField> createState() => _SiteSearchFieldState();
}

class _SiteSearchFieldState extends State<SiteSearchField> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _panel = OverlayPortalController();
  final _link = LayerLink();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (_focus.hasFocus) {
        _panel.show();
      } else {
        _panel.hide();
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _close() => _focus.unfocus();

  void _submit(String query) {
    _close();
    if (query.trim().isNotEmpty) openCatalog(context, query: query.trim(), title: '« ${query.trim()} »');
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: widget.maxWidth),
      child: LayoutBuilder(builder: (context, constraints) {
        return CompositedTransformTarget(
          link: _link,
          child: OverlayPortal(
            controller: _panel,
            overlayChildBuilder: (_) => CompositedTransformFollower(
              link: _link,
              targetAnchor: Alignment.bottomLeft,
              offset: const Offset(0, 6),
              child: Align(
                alignment: Alignment.topLeft,
                // Clicks in the panel must not count as "outside" the field (that would close it).
                child: TextFieldTapRegion(
                  child: SizedBox(
                    width: constraints.maxWidth,
                    child: Material(
                      color: Colors.white,
                      elevation: 8,
                      borderRadius: BorderRadius.circular(8),
                      clipBehavior: Clip.antiAlias,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 520),
                        child: ValueListenableBuilder(
                          valueListenable: _text,
                          builder: (_, value, __) => SearchSuggestions(
                            query: value.text,
                            onSearch: _submit,
                            onNavigate: _close,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            child: TextField(
              controller: _text,
              focusNode: _focus,
              textInputAction: TextInputAction.search,
              onSubmitted: _submit,
              decoration: InputDecoration(
                hintText: context.tr('search_hint'),
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                filled: true,
                fillColor: focused ? Colors.white : BmColors.surface,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: BmColors.ink, width: 1.2),
                ),
                suffixIcon: focused
                    ? IconButton(
                        tooltip: context.tr('cancel'),
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _text.clear();
                          _close();
                        },
                      )
                    : null,
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// Phones: a full page with the field at the top and the same suggestions.
void openSearchPage(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const _SearchPage()));

class _SearchPage extends StatefulWidget {
  const _SearchPage();

  @override
  State<_SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<_SearchPage> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit(String query) {
    if (query.trim().isEmpty) return;
    Navigator.of(context).pop();
    openCatalog(context, query: query.trim(), title: '« ${query.trim()} »');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _text,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: _submit,
          decoration: InputDecoration(
            hintText: context.tr('search_hint'),
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
        ),
      ),
      body: ValueListenableBuilder(
        valueListenable: _text,
        builder: (_, value, __) => SearchSuggestions(
          query: value.text,
          onSearch: _submit,
          onNavigate: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }
}

/// Empty query: shortcuts to the categories. Otherwise: the first matching items, refreshed as you type.
class SearchSuggestions extends StatefulWidget {
  const SearchSuggestions({super.key, required this.query, required this.onSearch, required this.onNavigate});

  final String query;
  final ValueChanged<String> onSearch;

  /// Called before opening a product or a category from the panel.
  final VoidCallback onNavigate;

  @override
  State<SearchSuggestions> createState() => _SearchSuggestionsState();
}

class _SearchSuggestionsState extends State<SearchSuggestions> {
  Timer? _debounce;
  List<Product> _items = [];
  int _total = 0;
  bool _loading = false;
  String _searched = '';

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(SearchSuggestions old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) _schedule();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _schedule() {
    _debounce?.cancel();
    final q = widget.query.trim();
    if (q.length < 2) {
      setState(() {
        _items = [];
        _searched = '';
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 250), () => _search(q));
  }

  Future<void> _search(String q) async {
    try {
      final res = await context.read<ApiClient>().get('/products', query: {'q': q, 'pageSize': 6}) as Json;
      final page = Paged.fromJson(res, Product.fromJson);
      if (!mounted || widget.query.trim() != q) return;
      setState(() {
        _items = page.items;
        _total = page.total;
        _searched = q;
      });
    } catch (_) {
      if (mounted) setState(() => _items = []);
    } finally {
      if (mounted && widget.query.trim() == q) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.lang;
    final q = widget.query.trim();

    if (q.length < 2) {
      final categories = context.watch<CategoriesController>();
      return ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(20),
        children: [
          for (final d in categories.departments) ...[
            Text(d.name(lang).toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 1)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in categories.childrenOf(d.id))
                  CategoryChip(
                    category: c,
                    onTap: () {
                      widget.onNavigate();
                      openCatalog(context, categoryId: c.id, title: c.path(lang));
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ],
      );
    }

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (_loading && _items.isEmpty)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
        else if (_items.isEmpty && _searched == q)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(context.tr('no_results_for', {'q': q}), style: const TextStyle(color: BmColors.muted)),
          ),
        for (final p in _items)
          InkWell(
            onTap: () {
              widget.onNavigate();
              openProduct(context, p.id);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  SizedBox(width: 44, height: 58, child: BmImage(p.image, radius: 4)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500)),
                        Text(
                          [p.category?.path(lang), p.size].whereType<String>().join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: BmColors.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Text(formatKes(p.price), style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        if (_items.isNotEmpty) ...[
          const Divider(height: 16),
          TextButton.icon(
            onPressed: () => widget.onSearch(q),
            icon: const Icon(Icons.arrow_forward, size: 18),
            label: Text(context.tr('see_all_results', {'n': _total, 'q': q})),
          ),
        ],
      ],
    );
  }
}
