import 'package:babymama_core/babymama_core.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier;

/// Category tree loaded once: departments (Women, Men, Kids) and their sub-categories.
class CategoriesController extends ChangeNotifier {
  CategoriesController(this._api);

  final ApiClient _api;
  List<Category> _all = [];
  bool _loading = false;

  List<Category> get all => _all;

  /// Top-level categories, in the order set by the admin.
  List<Category> get departments => _all.where((c) => c.parentId == null).toList();

  List<Category> childrenOf(String id) => _all.where((c) => c.parentId == id).toList();

  Category? byId(String? id) => id == null ? null : _all.where((c) => c.id == id).firstOrNull;

  /// The department a category belongs to (itself for a department).
  Category? departmentOf(String? id) {
    final c = byId(id);
    if (c == null) return null;
    return c.parentId == null ? c : byId(c.parentId);
  }

  Future<void> load() async {
    if (_loading || _all.isNotEmpty) return;
    _loading = true;
    try {
      final list = await _api.get('/categories') as List;
      _all = list.whereType<Json>().map(Category.fromJson).toList();
      notifyListeners();
    } catch (_) {
      // The shop still works without the menu; the next screen that needs it retries.
    } finally {
      _loading = false;
    }
  }
}
