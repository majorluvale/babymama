import 'package:babymama_core/babymama_core.dart';
import 'package:flutter/foundation.dart';

/// Favorite product ids of the signed-in customer, shared by every screen.
class FavoritesController extends ChangeNotifier {
  FavoritesController(this.api, this.session) {
    session.addListener(_onSessionChanged);
    _onSessionChanged();
  }

  final ApiClient api;
  final Session session;
  Set<String> _ids = {};
  String? _userId;

  bool isFavorite(String productId) => _ids.contains(productId);

  void _onSessionChanged() {
    final userId = session.user?.id;
    if (userId == _userId) return;
    _userId = userId;
    _ids = {};
    notifyListeners();
    if (userId != null) _load();
  }

  Future<void> _load() async {
    try {
      final list = await api.get('/me/favorites') as List;
      _ids = list.whereType<Map<String, dynamic>>().map((j) => '${j['id']}').toSet();
      notifyListeners();
    } catch (_) {
      // Favorites are not critical.
    }
  }

  Future<void> toggle(String productId) async {
    final wasFavorite = _ids.contains(productId);
    wasFavorite ? _ids.remove(productId) : _ids.add(productId);
    notifyListeners();
    try {
      if (wasFavorite) {
        await api.delete('/me/favorites/$productId');
      } else {
        await api.post('/me/favorites/$productId');
      }
    } catch (_) {
      wasFavorite ? _ids.add(productId) : _ids.remove(productId);
      notifyListeners();
      rethrow;
    }
  }

  @override
  void dispose() {
    session.removeListener(_onSessionChanged);
    super.dispose();
  }
}
