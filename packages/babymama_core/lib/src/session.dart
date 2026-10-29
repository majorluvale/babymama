import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'models.dart';

/// Signed-in user + JWT, persisted on the device.
class Session extends ChangeNotifier {
  Session(this.api, {this.storageKey = 'bm_token'});

  final ApiClient api;
  final String storageKey;
  BmUser? user;

  bool get isLoggedIn => user != null;

  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(storageKey);
    if (token == null) return;
    api.token = token;
    try {
      user = BmUser.fromJson(await api.get('/auth/me') as Json);
    } on ApiException catch (e) {
      if (e.status == 401 || e.status == 403) await _clear();
    }
    notifyListeners();
  }

  Future<void> login(String email, String password) =>
      _authenticate(api.post('/auth/login', {'email': email.trim(), 'password': password}));

  Future<void> register({
    required String name,
    required String email,
    required String password,
    String? phone,
    String? locale,
  }) =>
      _authenticate(api.post('/auth/register', {
        'name': name.trim(),
        'email': email.trim(),
        'password': password,
        if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        if (locale != null) 'locale': locale,
      }));

  Future<void> loginWithGoogle({String? idToken, String? accessToken, String? locale}) =>
      _authenticate(api.post('/auth/google', {
        if (idToken != null) 'idToken': idToken,
        if (accessToken != null) 'accessToken': accessToken,
        if (locale != null) 'locale': locale,
      }));

  Future<void> refreshUser() async {
    user = BmUser.fromJson(await api.get('/auth/me') as Json);
    notifyListeners();
  }

  Future<void> updateProfile(Json data) async {
    user = BmUser.fromJson(await api.patch('/auth/me', data) as Json);
    notifyListeners();
  }

  Future<void> logout() async {
    await _clear();
    notifyListeners();
  }

  Future<void> _authenticate(Future<dynamic> request) async {
    final res = await request as Json;
    api.token = res['token'] as String;
    user = BmUser.fromJson(res['user'] as Json);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, api.token!);
    notifyListeners();
  }

  Future<void> _clear() async {
    api.token = null;
    user = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(storageKey);
  }
}
