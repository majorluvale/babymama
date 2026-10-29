import 'dart:convert';

import 'package:babymama_core/babymama_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CartLine {
  CartLine({
    required this.kind,
    required this.id,
    required this.title,
    required this.unitPrice,
    required this.quantity,
    required this.maxQuantity,
    this.image,
    this.subtitle,
  });

  factory CartLine.fromJson(Json j) => CartLine(
        kind: '${j['kind']}',
        id: '${j['id']}',
        title: '${j['title']}',
        unitPrice: (j['unitPrice'] as num).toInt(),
        quantity: (j['quantity'] as num).toInt(),
        maxQuantity: (j['maxQuantity'] as num).toInt(),
        image: j['image'] as String?,
        subtitle: j['subtitle'] as String?,
      );

  /// 'product' or 'bundle'
  final String kind;
  final String id;
  final String title;
  final int unitPrice;
  int quantity;
  final int maxQuantity;
  final String? image;
  final String? subtitle;

  String get key => '$kind:$id';
  bool get isBundle => kind == 'bundle';

  Json toJson() => {
        'kind': kind,
        'id': id,
        'title': title,
        'unitPrice': unitPrice,
        'quantity': quantity,
        'maxQuantity': maxQuantity,
        'image': image,
        'subtitle': subtitle,
      };
}

/// Shopping cart kept on the device. Prices and stock are re-checked by the API (/orders/quote).
class CartController extends ChangeNotifier {
  static const _key = 'bm_cart';
  final List<CartLine> _lines = [];

  List<CartLine> get lines => List.unmodifiable(_lines);
  bool get isEmpty => _lines.isEmpty;
  int get count => _lines.fold(0, (s, l) => s + l.quantity);
  int get subtotal => _lines.fold(0, (s, l) => s + l.unitPrice * l.quantity);

  /// Changes whenever the content changes; used to refresh the server quote.
  String get signature => _lines.map((l) => '${l.key}x${l.quantity}').join(',');

  int quantityOf(String kind, String id) {
    for (final l in _lines) {
      if (l.kind == kind && l.id == id) return l.quantity;
    }
    return 0;
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return;
      final list = jsonDecode(raw) as List;
      _lines
        ..clear()
        ..addAll(list.whereType<Map<String, dynamic>>().map(CartLine.fromJson));
    } catch (_) {
      _lines.clear();
    }
  }

  /// Returns false when the stock limit is reached.
  bool addProduct(Product p, {int quantity = 1}) {
    return _add(CartLine(
      kind: 'product',
      id: p.id,
      title: p.title,
      unitPrice: p.price,
      quantity: quantity,
      maxQuantity: p.stock,
      image: p.image,
      subtitle: [p.size, p.brand].whereType<String>().join(' · '),
    ));
  }

  bool addBundle(Bundle b, String lang) {
    return _add(CartLine(
      kind: 'bundle',
      id: b.id,
      title: b.localizedTitle(lang),
      unitPrice: b.price,
      quantity: 1,
      maxQuantity: b.available,
      image: b.imageUrl,
      subtitle: '${b.items.length} articles',
    ));
  }

  bool _add(CartLine line) {
    final existing = _lines.where((l) => l.key == line.key).toList();
    if (existing.isNotEmpty) {
      final l = existing.first;
      if (l.quantity >= l.maxQuantity) return false;
      l.quantity += 1;
    } else {
      if (line.maxQuantity <= 0) return false;
      _lines.add(line);
    }
    _changed();
    return true;
  }

  void setQuantity(String key, int quantity) {
    final idx = _lines.indexWhere((l) => l.key == key);
    if (idx < 0) return;
    if (quantity <= 0) {
      _lines.removeAt(idx);
    } else {
      _lines[idx].quantity = quantity.clamp(1, _lines[idx].maxQuantity);
    }
    _changed();
  }

  void remove(String key) => setQuantity(key, 0);

  void clear() {
    _lines.clear();
    _changed();
  }

  Json toPayload() => {
        'items': [
          for (final l in _lines.where((l) => !l.isBundle)) {'productId': l.id, 'quantity': l.quantity},
        ],
        'bundles': [
          for (final l in _lines.where((l) => l.isBundle)) {'bundleId': l.id, 'quantity': l.quantity},
        ],
      };

  void _changed() {
    notifyListeners();
    SharedPreferences.getInstance().then((prefs) => prefs.setString(_key, jsonEncode(_lines.map((l) => l.toJson()).toList())));
  }
}
